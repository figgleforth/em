# todo) don't store token on any Ast node. instead, store the token's raw string. tired of not knowing whether Ast.whatever is a token or the raw string. ugh! search :token on this file and you'll see!

class Ast
    def to_s
        "Ast"
    end
end


class Program < Ast
    attr_accessor :expressions


    def initialize
        @expressions = []
    end


    def to_s
        "Program:\n\n".tap do |program|
            expressions.each do |expr|
                program << "#{expr}\n"
            end
        end
    end
end


class Ast_Expression < Ast
    attr_accessor :short_form,
                  :inferred_type


    def initialize
        @short_form = false
    end


    def == other
        other == self.class
    end


    def evaluate
        puts "Trying to evaluate self #{self}"
        raise NotImplementedError
    end
end


class StringExpr < Ast_Expression
    attr_accessor :token


    def to_s
        long  = "Str(#{inspect})"
        short = "#{token.string}"
        short_form ? short : long
    end


    def evaluate
        token.string
    end
end


class NumberExpr < Ast_Expression
    attr_accessor :token


    def number
        # @todo convert to number
        token&.string
    end


    def to_s
        long  = "Num(#{token.string})"
        short = "#{token.string}"
        short_form ? short : long
    end


    # https://stackoverflow.com/a/18533211/1426880
    def string_to_float
        Float(token.string)
        i, f = token.string.to_i, token.string.to_f
        i == f ? i : f
    rescue ArgumentError
        self
    end


    def evaluate
        string_to_float
    end
end


class ObjectExpr < Ast_Expression
    attr_accessor :type, :base_type, :compositions, :statements, :is_api


    def initialize
        super
        @base_type    = nil
        @type         = nil
        @compositions = []
        @statements   = []
        @is_api       = false
    end


    def to_s
        type_label = is_api ? 'Api' : 'Obj'
        "#{short_form ? '' : type_label}(#{type}".tap do |str|
            str << ", base: #{base_type}" if base_type
            str << ", APIs(#{compositions.count}): #{compositions.map(&:to_s)}" unless compositions.empty?
            str << ", exprs(#{statements.count}): #{statements.map(&:to_s)}" unless statements.empty?
            str << ')'
        end
    end
end


class FunctionExpr < Ast_Expression
    attr_accessor :name, :return_type, :parameters, :statements


    def initialize
        super
        @parameters = []
        @statements = []
        @short_form = true
    end


    def to_s
        # "Method(#{name}, return_type: #{return_type.to_s}, params(#{parameters.count}): #{parameters.map(&:to_s)}), stmts(#{statements.count}): #{statements.map(&:to_s)})"
        short = "#{name}(".tap do |str|
            str << "returns: #{return_type || 'nil'}"
            str << ", params(#{parameters.count}): #{parameters.map(&:to_s)}" unless parameters.empty?
            # str << ", stmts(#{statements.count})" unless statements.empty?
            str << ", stmts(#{statements.count}): #{statements.map(&:to_s)}" unless statements.empty?
            # if statements.one?
            #     str << ", stmts(#{statements.count}): #{statements.map(&:to_s)}"
            # else
            #     str << ", stmts(#{statements.count}): [first: #{statements.first.to_s}, last: #{statements.last.to_s}]"
            # end
            # end
            str << ')'
            str << " -> (#{return_type})" if return_type
        end

        short_form ? short : inspect
    end
end


class CommaSeparatedExpr < Ast_Expression
    attr_accessor :expressions,
                  :count


    def expressions= val
        @expressions = val
        @count       = val.count
    end
end


class FunctionParamExpr < Ast_Expression
    attr_accessor :name, :label, :type


    def to_s
        "#{short_form ? '' : 'Param'}(name: #{name}".tap do |str|
            str << ", type: #{type}" if type
            str << ", label: #{label}" if label
            str << ')'
        end
    end
end


class FunctionArgExpr < Ast_Expression
    attr_accessor :expression, :label


    def to_s
        "#{short_form ? '' : 'Arg'}(#{expression.to_s}".tap do |str|
            str << ", label: #{label}" if label
            str << ')'
        end
    end
end


class FunctionCallExpr < Ast_Expression
    attr_accessor :function_name, :arguments


    def initialize
        super
        @arguments = []
    end


    def to_s
        "#{short_form ? '' : 'FunCall'}(name: #{function_name}".tap do |str|
            str << ", args(#{arguments.count}): #{arguments.map(&:to_s)}" unless arguments.empty?
            str << ')'
        end
    end
end


class AssignmentExpr < Ast_Expression
    attr_accessor :name, :type, :value


    def to_s
        "#{short_form ? '' : 'Var'}(#{name.string}".tap do |str|
            if type
                str << ": #{type.string}"
            end

            str << " = #{value ? value : value.inspect}"

            str << ")"
        end
    end


    def evaluate
        value&.evaluate
    end
end


class UnaryExpr < Ast_Expression
    require_relative '../lexer/tokens'
    attr_accessor :operator, :expression


    def to_s
        long  = "UE(#{operator.string}#{expression})"
        short = "(#{operator.string}#{expression})"
        short_form ? short : long
    end


    def evaluate
        case operator.string
            when '-'
                expression.evaluate * -1
            when '+'
                expression.evaluate * +1
            when '~'
                raise 'Dunno how to ~'
            when '!'
                not expression.evaluate
            else
                puts "what??? #{operator}"
                raise "UnaryExpr(#{operator.string.inspect}) not implemented"
        end
    end
end


class BinaryExpr < Ast_Expression
    attr_accessor :operator, :left, :right


    def to_s
        long  = "BE(#{left} #{operator.string} #{right})"
        short = "(#{left}#{operator.string}#{right})"
        short_form ? short : long
    end


    def evaluate
        if right.evaluate == nil or right.evaluate == 'nil'
            raise "BinaryExprNode trying to `#{operator.string}` with nil"
        end

        case operator.string
            when '+'
                left.evaluate + right.evaluate
            when '-'
                left.evaluate - right.evaluate
            when '*'
                left.evaluate * right.evaluate
            when '/'
                left.evaluate / right.evaluate
            when '%'
                left.evaluate % right.evaluate
            when '&&'
                left.evaluate && right.evaluate
            else
                raise "BinaryExprNode(#{operator.string.inspect}) not implemented"
        end
    end
end


class IdentifierExpr < Ast_Expression
    require_relative '../lexer/lexer'
    attr_accessor :name


    def to_s
        short_form ? "#{name}" : "IdentExpr(#{name})"
    end


    def evaluate
        if Lexer::KEYWORDS.include? name
            return nil if name == 'nil'
            return true if name == 'true'
            return false if name == 'false'
        else
            name
        end
    end
end
