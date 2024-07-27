# Turns string of code into tokens
class Parser
    require_relative '../lexer/tokens'
    require_relative 'exprs'

    attr_accessor :i, :buffer, :expressions, :eaten_this_iteration


    def initialize buffer = []
        @i                    = 0 # index of current token
        @buffer               = buffer
        @expressions          = []
        @eaten_this_iteration = []
    end


    def to_ast
        parse_until EOF_Token
    end


    # region Parsing Helpers

    # makes a new Parser and sets its tokens to the current remainder
    def new_parser_with_remainder_as_buffer
        Parser.new remainder
    end


    def debug
        "\n\nCURR TOKEN:\n\t#{curr.inspect}
        \nPREV TOKEN:\n\t#{prev.inspect}
        \nEATEN THIS ITERATION of #parse_expre:\n\t#{@eaten_this_iteration.map(&:to_s)}"
    end


    # buffer[i - 1]
    def prev
        peek -1
    end


    # buffer[i]
    def curr
        peek 0
    end


    # buffer[i..]
    def remainder
        @buffer[@i..]
    end


    # whether there are tokens remaining to be parsed
    def tokens?
        @i < (@buffer&.length || 0)
    end


    def eat_past_newlines
        eat while curr? "\n"
    end


    # looks at token without eating, can look backwards as well but peek index is clamped to buffer. if accumulated, returns an array of tokens. otherwise returns a single token
    def peek ahead = 0
        raise 'Parser.buffer is nil' unless buffer

        index = ahead.clamp(0, @buffer.count)
        @buffer[@i + index]
    end


    # looks ahead `count` tokens, without consuming them. cannot peek backwards
    def peek_many count = 2
        raise 'Parser.buffer is nil' unless buffer

        remainder.slice 0, count
    end


    # slices buffer until specified token, so it isn't included in the result. doesn't actually consume the buffer, you still have to do that by calling eat. easier to iterate this than fuck with the actual pointer in the buffer
    def peek_until token = "\n"
        remainder.slice_before do |t|
            t == token
        end.to_a.first
    end


    # slices buffer past specified token, so it is included in the result. doesn't actually consume the buffer, you still have to do that by calling eat. easier to iterate this than fuck with the actual pointer in the buffer
    def peek_past token = "\n"
        remainder.slice_after do |t|
            t == token
        end.to_a.first
    end


    # uses peek_until to get count of tokens until specified token, then adds that count to the buffer pointer @i
    def eat_until token = "\n"
        @i += peek_until(token).count
    end


    # uses peek_past to get count of tokens until it passes specified token, then adds that count to the buffer pointer @i
    def eat_past token = "\n"
        @i += peek_past(token).count
    end


    # checks whether the remainder buffer contains the exact sequence of tokens. if one of the arguments is an array then that token in the sequence can be either of the two. eg: ident, [:, =, :=]
    def curr? * sequence
        remainder.slice(0, sequence.count).each_with_index.all? do |token, index|
            if sequence[index].is_a? Array
                sequence[index].any? do |sequence_element|
                    if sequence_element.is_a? Symbol
                        token == sequence_element.to_s
                    else
                        token == sequence_element
                    end
                end
            else
                if sequence[index].is_a? Symbol
                    token == sequence[index].to_s
                else
                    token == sequence[index]
                end
            end
        end
    end


    # eats a specific sequence of tokens, either Token class or exact string. eg: eat StringLiteralToken, eat '.'. etc
    # idea: support sequence of elements where an element can be one of many, like the sequence [IdentifierToken, [:=, =]]
    def eat * sequence
        if sequence.nil? or sequence.empty? or sequence.one?
            eaten = curr
            if sequence&.one? and eaten != sequence[0]
                puts debug
                raise "Parser expected token(s): #{sequence} but got: #{eaten}" # todo: improve this error
            end
            @i    += 1
            eaten_this_iteration << eaten
            return eaten
        end

        [].tap do |result|
            # Usage:
            #   sequence =
            #     eat '}'
            #     eat %w(} end)
            sequence.each do |expected|
                unless curr == expected
                    current   = "\n\nExpected #{expected} but got #{curr}"
                    remaining = "\n\nREMAINING:\n\t#{remainder.map(&:to_s)}"
                    progress  = "\n\nPARSED SO FAR:\n\t#{expressions[3..]}"
                    raise "#{current}#{remaining}#{progress}" unless curr == expected
                end

                eaten = curr
                result << eaten
                eaten_this_iteration << eaten
                @i += 1
            end
        end
    end


    # endregion

    # region Sequence Parsing

    def parse_block until_token = '}'
        Block_Expr.new.tap do |it|
            parser         = new_parser_with_remainder_as_buffer
            stmts          = parser.parse_until until_token
            @i             += parser.i
            it.expressions = stmts

            # make sure the block's compositions are derived from the expressions parsed in the block
            it.compositions = stmts.select do |s|
                s.is_a? Composition_Expr
            end
        end
    end


    # def make_typed_var_decl_ast # todo: support types
    #     Assignment_Expr.new.tap do |node|
    #         tokens    = eat Identifier_Token, ':', Identifier_Token
    #         node.name = tokens[0].string
    #         node.type = tokens[2]
    #
    #         if curr? '='
    #             eat '='
    #
    #             if curr? %W(; \n)
    #                 raise "Expected expression after ="
    #             end
    #             node.expression = parse_expression
    #         end
    #     end
    # end

    def make_assignment_ast
        Assignment_Expr.new.tap do |it|
            it.name = eat(Identifier_Token) # todo) store the Token and not just the string

            if curr? '=;'
                eat '=;'
                it.expression = Nil_Expr.new
            elsif curr? '=' and eat '='
                if curr? "\n"
                    code = (buffer << curr).join(' ')
                    raise "Expected expression after `#{buffer[1]}` but got `#{curr}` in\n\n```\n#{code}\n```"
                else
                    it.expression = parse_expression
                end
            else
                current   = "Expected = with an expression or ; to terminate the var declaration"
                unhandled = "UNHANDLED TOKEN:\n\t#{curr.inspect}"
                remaining = "REMAINING:\n\t#{remainder.map(&:to_s)}"
                progress  = "PARSED SO FAR:\n\t#{expressions}"
                raise "\n\n#{current}\n\n#{unhandled}\n\n#{remaining}\n\n#{progress}"
            end
        end
    end


    def make_enum_ast
        if curr? Identifier_Token, '{'
            Enum_Expr.new.tap do |it|
                it.name = eat(Identifier_Token)
                eat '{'
                eat_past_newlines
                until curr? '}'
                    it.constants << make_enum_ast
                    it.constants.compact!
                end
                eat '}'
                eat_past_newlines
            end

        elsif curr? Identifier_Token, '='
            constant_assignment = make_assignment_ast
            eat_past_newlines
            constant_assignment

        elsif curr? Identifier_Token
            # these are enum constants without a value. eg) ENV { DEV, PROD } which can still be used as constants ENV.DEV and ENV.PROD, but they don't have a value set.
            Assignment_Expr.new.tap do |it|
                it.name = eat(Identifier_Token)
                eat_past_newlines
            end

        elsif curr? ',' and eat ','
            eat_past_newlines

        else
            raise "Parser#make_enum_ast not sure about #{curr.inspect}"
        end
    end


    def make_string_or_number_or_boolean_literal_ast
        if curr == String_Token
            String_Literal_Expr.new
        elsif curr == Boolean_Token
            Boolean_Literal_Expr.new
        else
            Number_Literal_Expr.new
        end.tap do |it|
            it.string = eat.string
        end
    end


    def make_unary_expr_ast
        Unary_Expr.new.tap do |node|
            node.operator   = eat(Ascii_Token).string
            node.expression = parse_expression 6 # this cannot use #precedence_for because it would return the same precedence as the binary operators of the same symbol, but we need to be able to be distinguish between the unary. there's probably a better way to do this, but who cares.
        end
    end


    def make_composition_ast
        Composition_Expr.new.tap do |it|
            it.operator = eat.string # > + - # * & ~
            # puts "what if we eat expression"
            # expr = parse_expression
            # puts "expr #{expr.inspect}"
            it.expression = parse_expression

            if curr? 'as' and eat
                it.alias_identifier = eat(Identifier_Token)
            end
        end
    end


    def make_inline_composition_ast
        Composition_Expr.new.tap do |it|
            ident         = eat.string
            it.identifier = Identifier_Expr.new.tap do |id|
                id.string = ident[1..]
            end
            it.operator   = ident[0]
        end
    end


    def make_macro_ast # are percent literals, where the body is made of identifiers separated by spaces and enclosed in parens. like %s(boo hoo)
        if curr? '>~' or curr? '>!' or curr? '>!!' or curr? '>!!!'
            Macro_Command_Expr.new.tap do |it|
                it.name       = eat(Macro_Token).string
                it.expression = parse_expression # todo) it would be cool to be able to comma separate expressions here. it feels nicer to type a comma than a plus, because the plus requires holding shift
            end
        else
            Macro_Expr.new.tap do |it|
                it.name = eat(Macro_Token).string

                eat '('
                while curr? Identifier_Token
                    it.identifiers << eat(Identifier_Token).string
                    eat if curr? ','
                end

                case it.name
                    when '%S'
                        it.identifiers.map!(&:upcase)
                    when '%s'
                        it.identifiers.map!(&:downcase)
                    when '%V'
                        # ['BOO', 'HOO']
                    when '%v'
                        # ['boo', 'hoo']
                    when '%W'
                        # ["BOO", "HOO"]
                    when '%w'
                        # ["boo", "hoo"]
                    when '%d'
                        # {boo: nil, hoo: nil}
                    when '%D'
                        # {BOO: nil, HOO: nil}
                    when '%'
                        # %(1, 2, 3) tuples
                    else
                        raise "Parse#make_macro_ast unknown macro #{it.name}"
                end

                eat ')'
            end
        end
    end


    def make_function_call_ast
        Block_Call_Expr.new.tap do |node|
            node.name = eat Identifier_Token
            eat '('
            node.arguments = make_array_of_block_argument_exprs
            eat ')'
        end
    end


    # Ident ( > Ident (, Ident) )
    #   { ... }
    def make_class_ast is_api_decl = false
        Class_Expr.new.tap do |it|
            it.name = eat(Identifier_Token)

            if curr? '>' and eat '>'
                raise 'Parent must be a Class' unless curr.object?
                it.base_class = eat(Identifier_Token)
            end

            eat '{'
            it.block = parse_block '}'

            # make sure the class's compositions are derived from the expressions parsed in the block
            it.compositions = it.block.expressions.select do |expr|
                expr.is_a? Composition_Expr
            end

            eat '}'
        end
    end


    def make_comma_separated_ast
        Comma_Separated_Expr.new.tap do |node|
            node.expressions << parse_block(%w[, )])
            while curr? ','
                eat ','
                node.expressions << parse_block(%w[, )])
            end
            eat ')'
        end
    end


    def make_array_of_block_argument_exprs
        [].tap do |args|
            while not curr? ')'
                args << Block_Arg_Expr.new.tap do |param|
                    if curr? Identifier_Token, ':' #, Token
                        param.label = eat Identifier_Token
                        eat ':'
                    end

                    param.expression = if curr? Token, ','
                                           parse_block ','
                                       elsif curr? Token, ')'
                                           parse_block ')'
                                       else
                                           parse_block %w[, )]
                                       end.expressions[0]
                end

                eat if curr? ','
            end
        end
    end


    def make_array_of_block_param_declaration_exprs
        [].tap do |params|
            while curr? Identifier_Token or curr? '&', Identifier_Token
                params << Block_Param_Decl_Expr.new.tap do |it|
                    if curr? Identifier_Token and curr.composition?
                        it.composition = true
                        ident          = eat.string
                        it.name        = ident[1..] # excludes the & or ~
                    elsif curr? Identifier_Token and not curr.composition? and peek(1) == Identifier_Token and peek(1).composition?
                        it.composition = true
                        it.label       = eat(Identifier_Token)
                        ident          = eat.string
                        it.name        = ident[1..]
                    elsif curr? Identifier_Token, '&', Identifier_Token
                        it.composition = true
                        it.label       = eat(Identifier_Token)
                        eat '&'
                        it.name = eat(Identifier_Token)
                    elsif curr? '&', Identifier_Token
                        it.composition = true
                        eat '&'
                        it.name = eat(Identifier_Token)
                    elsif curr? Identifier_Token, Identifier_Token
                        it.label = eat(Identifier_Token)
                        it.name  = eat(Identifier_Token)
                    elsif curr? Identifier_Token
                        it.name = eat(Identifier_Token)
                    end

                    if curr? '='
                        eat '='
                        it.default_expression = parse_block(%W(, \n ->)).expressions[0]
                    end

                    eat ',' if curr? ','
                end
            end
        end
    end


    def make_inline_block_ast
        # ident -> expression
        Block_Expr.new.tap do |it|
            it.name = eat Identifier_Token
            eat '->'
            it.expressions = [parse_expression]
        end
    end


    def make_block_ast
        # ident { ... }
        # ident { -> ... }
        # ident { in, in -> ... }
        Block_Expr.new.tap do |it|
            if curr? Identifier_Token, '{'
                it.name = eat(Identifier_Token, '{')[0]
            elsif curr? '{' # anonymous function
                eat '{'
            end

            has_params = (peek_until '}').any? do |t|
                t == '->' or t == '::'
            end

            eat_past_newlines
            it.parameters = make_array_of_block_param_declaration_exprs if has_params and not curr? '->'

            # make sure function expr also knows about the compositions in the parameters
            it.compositions = it.parameters.select do |param|
                param.composition
            end.map do |param|
                param.name
            end

            eat '->' if curr? '->'
            eat '::' if curr? '::'

            block = parse_block
            eat '}'

            it.compositions << block.compositions
            it.expressions = block.expressions
            it.compositions.flatten!
        end
    end


    def make_block_hook_ast
        Block_Hook_Expr.new.tap do |it|
            it.identifier = eat.string
            raise 'Expected target function identifier after @before keyword' unless curr? Identifier_Token
            it.target_function_identifier = eat(Identifier_Token)
            eat_past_newlines
        end
    end


    def make_conditional_ast is_while_conditional = false
        klass = if is_while_conditional
            While_Expr
        else
            Conditional_Expr
        end
        klass.new.tap do |it|
            eat if curr? 'if' or curr? 'while'

            if curr? Identifier_Token, '{'
                identifier   = eat Identifier_Token
                it.condition = Identifier_Expr.new.tap do |id|
                    id.string = identifier.string
                    # id.tokens << identifier
                end
                eat '{'
            else
                potential = parse_expression
                if potential.is_a? Block_Expr and potential.named?
                    it.condition = Identifier_Expr.new.tap do |id|
                        id.string = potential.name.string
                    end
                elsif potential.is_a? Binary_Expr and potential.operator == '.' and potential.right.is_a? Block_Expr and potential.right.named?
                    it.condition = Identifier_Expr.new.tap do |id|
                        id.string = potential.right.name.string
                    end
                else
                    it.condition = potential
                end

                eat '{' if curr? '{'
            end

            eat_past_newlines
            it.when_true = parse_block %w(} else elsif elif ef elswhile)

            if curr? 'else'
                eat 'else'
                it.when_false = parse_block '}'
                eat '}'
            elsif curr? '}'
                eat '}'
            elsif curr? 'elsif' or curr? 'elif' or curr? 'elswhile'
                while curr? 'elsif' or curr? 'elif' or curr? 'elswhile'
                    eat # elsif or elif
                    raise 'Expected condition in the elsif' if curr? "\n" or curr? ';' or curr? '}'
                    it.when_false = make_conditional_ast is_while_conditional
                end
            else
                raise "\n\nYou messed your if/elsif/else up\n" + debug
            end
        end
    end


    def make_while_ast
        While_Expr.new.tap do |it|
            eat 'while' if curr? 'while'
            it.condition = parse_block("\n").expressions[0]
            it.when_true = parse_block %w(elswhile else })

            if curr? 'else'
                eat 'else'
                it.when_false = parse_block '}'
                eat '}'
            elsif curr? '}'
                eat '}'
            elsif curr? 'elswhile'
                while curr? 'elswhile'
                    eat # elswhile
                    raise 'Expected condition in the elswhile' if curr? "\n" or curr? ";"
                    it.when_false = make_while_ast
                end
            else
                raise "\n\nYou messed your while/elswhile/else up\n" + debug
            end
        end
    end


    def make_dictionary_ast
        Dictionary_Literal_Expr.new.tap do |it|
            eat '{'

            eat_past_newlines
            while curr? Identifier_Token
                it.keys << eat(Identifier_Token).string

                if curr? %w(: =) and eat
                    eat_past_newlines
                    it.values << parse_expression
                else
                    it.values << nil
                end

                eat if curr? ','
                eat_past_newlines
            end

            eat '}'
        end
    end


    def make_array_literal_ast
        Array_Literal_Expr.new.tap do |it|
            eat '['
            if curr? ']' and eat
                return it
            end
            it.elements << parse_expression
            while curr? ','
                eat ','
                it.elements << parse_expression
            end
            it.elements.compact! # parse_block can return nil, so this could be an array of nil values.
            eat ']' if curr? ']'
        end
    end


    def make_operator_overload_ast
        raise 'Operator overloading not implemented in Parser'
    end


    def peek_until_contains? until_token, contains
        peek_until(until_token).any? { |t| t == contains }
    end


    def peek_until_all? until_token, contains
        peek_until(until_token)[1..].all? { |t| t == contains }
    end


    # Array of precedences and symbols for that precedence. if the token provided matches one of the operator symbols then its precedence is returned. Nice reference: https://rosettacode.org/wiki/Operator_precedence
    def precedence_for token
        # note) this can be improved. for example, just order them in an array. I don't think I need any explicit number control, as long as the order is what it is currently
        # Lame explanation –
        # If the current prec is lower than the previously parsed operator, then that ends the previous expression
        # If the current prec is higher than the previously parsed operator, then that is a continuation of the expression
        [
          [0, %w(( ))],
          [1, %w([ ])],
          [1, %w(!)],
          [2, %w(< <= > >= == != === !==)],
          [4, %w(- +)],
          [5, %w(** * / %)],
          [7, %w(<< >>)],
          [10, %w(&)],
          [11, %w(^)],
          [12, %w(|)],
          [13, %w(&&)],
          [14, %w(||)],
          [17, %w(= += -= *= /= %= &= |= ^= <<= >>=)],
          [18, %w(,)],
          [20, %w(. .? .. .<)],
        ].find do |_, chars|
            chars.include?(token.string)
        end&.at(0)
    end


    def parse_expression starting_precedence = 0
        # def make_ast # note: any nils returned are effectively discarded because the array of parsed expressions is later compacted to get rid of nils.
        merge_comp  = (curr? '>', Identifier_Token and (peek(1).constant? or peek(1).object?))
        add_comp    = (curr? '+', Identifier_Token and (peek(1).constant? or peek(1).object?))
        remove_comp = (curr? '-', Identifier_Token and (peek(1).constant? or peek(1).object?))
        inline_comp = (curr? Identifier_Token and curr.composition?)

        ast = if curr? '{' and peek_until_contains? '}', '->'
            make_block_ast

        elsif curr? '{', '}'
            make_dictionary_ast

        elsif curr? '{' and peek_until_all? '}', Identifier_Token
            make_dictionary_ast

        elsif curr? '{' # all other { possibilities are exhausted, or handled inside other make_*_ast so this must be a dictionary
            make_dictionary_ast

        elsif curr? '['
            make_array_literal_ast

        elsif curr? '('
            # note: this parenthesized expression differs from the one for function calls in at least one way where the function call expressions will be iterated using a while loop, and this one here will recursively call #parse_expression
            paren      = eat '('
            precedence = precedence_for paren
            parse_expression(precedence).tap do
                eat ')'
            end
        elsif curr? 'while'
            # make_while_ast
            make_conditional_ast true

        elsif curr? 'if'
            make_conditional_ast

        elsif curr? Keyword_Token and curr.at_operator? and curr == '@before'
            make_block_hook_ast

        elsif curr? Keyword_Token and curr == 'nil'
            eat and Nil_Expr.new

        elsif curr? Keyword_Token and curr == 'operator'
            make_operator_overload_ast

        elsif add_comp or remove_comp or merge_comp
            make_composition_ast

        elsif inline_comp # this is parsed a tiny bit differently than the other comps, so it's okay to have a separate implementation. If I want to avoid this, I might have to change how this specific identifier is parsed. But this is okay for now
            make_inline_composition_ast

        elsif curr? '&', Identifier_Token and peek(1).member?
            raise 'Cannot compose a class with members, only other classes and enums'

        elsif curr? Identifier_Token, '=;'
            if curr.constant?
                raise 'Enums must be initialized as a collection or single value.'
            end
            make_assignment_ast

        elsif curr? Identifier_Token and curr.object? and (curr? Identifier_Token, '{' or curr? Identifier_Token, '>') # and not curr? Identifier_Token, '.' # Capitalized identifier. I'm explicitly ignoring the dot here because otherwise all object identifiers will expect an { next
            make_class_ast

        elsif curr? Identifier_Token, '{' and peek_until_contains? '}', '->'
            make_block_ast

        elsif curr? Identifier_Token, '->'
            make_inline_block_ast

        elsif curr? Identifier_Token, '=' # and curr.member? # lowercase identifier
            make_assignment_ast

        elsif (curr? Identifier_Token, '{' or curr? Identifier_Token, '=') and curr.constant? # UPPERCASE identifier
            make_enum_ast

        elsif curr? Identifier_Token, '('
            make_function_call_ast

        elsif curr? Ascii_Token and curr.respond_to?(:unary?) and curr.unary? # %w(- + ~ !)
            make_unary_expr_ast

        elsif curr? Macro_Token
            make_macro_ast

        elsif curr? String_Token or curr? Number_Token or curr? Boolean_Token
            make_string_or_number_or_boolean_literal_ast

        elsif curr? Comment_Token
            eat and nil

        elsif curr? %W(, ; \n) # ignoring the comma allows for expressions separated by commas. aka Delimiter_Token
            # todo) this might be the location where conditionals at the end of an expression are parsed? At this point, it is assumed that the previous expression was parsed, and it is the last thing in @expressions
            eat and nil

        elsif curr? Symbol_Token
            Symbol_Literal_Expr.new.tap do |node|
                node.string = eat.string
            end

        elsif curr? [Identifier_Token, '@']
            Identifier_Expr.new.tap do |node|
                ident           = eat
                node.string     = ident.string
                node.is_keyword = ident.is_a? Keyword_Token
            end

        elsif curr? ':', '+' or curr? ':', '-'
            raise "You used #{curr}#{peek(1)} but probably meant #{peek(1)}#{curr}"

        elsif curr? EOF_Token
            raise "Parser expected an expression but reached EOF"

            # elsif curr? ']'
            #     eat

        else
            raise "Parsing not implemented for #{curr.inspect}"
        end

        return if not ast

        # \n are eaten and return nil, so we have to terminate this expression early. Otherwise negative numbers are sometimes parsed as BE( - NUM) insteadof UE(-NUM)

        # if token after ast is a binary operator, then we build a binary expression
        while tokens?
            if curr? Ascii_Token and curr.binary? # or curr? '['
                curr_operator_prec = precedence_for(curr)
                break if curr_operator_prec <= starting_precedence # <= originally

                ast = Binary_Expr.new.tap do |it|
                    it.left     = ast
                    it.operator = eat(Ascii_Token).string
                    # raise 'Expected expression' if curr? "\n"
                    it.right    = parse_expression(curr_operator_prec) unless curr? ']'
                    eat if curr? ']'
                end
            else
                eat ']' if curr? ']'
                break
            end
        end

        ast
    end


    def parse_until until_token = EOF_Token
        expressions.tap do |s|
            while tokens? and curr != EOF_Token
                if until_token.is_a? Array
                    break if until_token.any? do |t|
                        curr == t
                    end
                else
                    break if curr == until_token
                end

                if (expr = parse_expression)
                    # puts "\nexpr #{expr.inspect}"
                    s << expr
                end
            end
        end.compact
    end
end
