**Summary**
- Create a `Time` instance from a string like `11:11pm`.
- Define a `Time` class with infix and postfix operators for parsing and modifying time.
- Use `#Time` to localize the scope and `-#Time` to remove it, with no return value from scoping expressions.
- Differentiate operators based on whether they are used on instances or non-instances, determined by the parameters.
- Adjust `Time` attributes and handle different contexts with custom operators.

---

I want to write `time = 11:11pm` and get back a `Time` instance.
```
Time {
   hour
   minute
   meridian
   
   MERIDIAN {
      AM,
      PM
   }
   
   operator infix : { left, right ->
      `pretend type-checking for a Number instances
      Time.tap {
         it.hour = left
         it.minute = right
      }
   }
   
   operator postfix pm { left ->
      `more pretend type-checking for a Time instance
      left.meridian = MERIDIAN.PM
      left
   }
}

#Time `localize Time scope, giving you access to the : operator
time = 11:22pm `Time(11:22pm)
time.hour `11
time.minute `22
time.meridian `pm
-#Time `remove Time scope
```
The reason this operator needs a `left` and `right` argument is because if it were declared on an instance of `Time` then it would only need a `right`, and it would need to be used on a `Time` instance. But in this form, you supply it both sides, and that lets you perform `Time` operations on non-`Time` instances.

I think `-#Class` is cool syntax, the implication is that it cancels out the `#Class`. Scoping and descoping expressions should be ignored as a return value, similar to how Ruby ignores comments. This is important because the last expression in any block is it's return value.

---

What about syntax for differentiating between this operator on `Time` instances or on two non-`Time` instances? I want to use the language structure itself is a form of configuration, so the context in which the operator is used depends on the params declared.

- `{left->}` means `./` is the right side, therefore this is called on an instance
- `{right->}` means `./` is the left side, also called on an instance
- `{left,right->}` means this operator takes two instances

```
Time {
   operator infix : { left -> }
   operator infix : { right -> }
   operator infix : { left, right -> }
}
```
Using the previous code as an example to explain. When `:` is used, the declaration with both `left` and `right` will be called. 
```
Time.now : 15 `called on instance
16 : Time.now `called on instance

#Time
11:22pm
-#Time
```
---
I imagine this could be powerful.
```
Time {
   operator infix : { left, right ->
      if left is Time
         left.second = right
      else
         Time.tap {
            it.hour = left
            it.minute = right
         }
      }
   }
}

Time.now `1:08pm

#Time
now.hour:22 `makes 1:22pm
11:now.minute `makes 11:08pm
now:42 `makes 1:08:42pm
-#Time
```
