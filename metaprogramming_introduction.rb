require 'demo_test_unit_extensions'

class MetaprogrammingIntroduction < Test::Unit::TestCase

=begin  
This is a demonstration of dynamic method definition using the private method
Module#define_method and an introduction to singleton classes (also known as
metaclasses). This is the basis of Ruby metaprogramming.

Note that I'm going to avoid use or discussion of Ruby's very important eval
methods in this article. This is only to reduce the scope of what's explained.
In practice I'd prefer module_eval or class_eval to reopening of classes or
modules or use of Object#send to invoke private methods.

Chapter 24 in the Pickaxe is your reference for the nuts and bolts of Ruby
classes. There's surprisingly little discussion of things you can do with
metaprogramming, but all the information you need is there. _why the lucky
stiff's Seeing Metaclasses Clearly is dense and opaque, but fun:
  http://whytheluckystiff.net/articles/seeingMetaclassesClearly.html
=end

  show "Calling define_method on a class adds an instance method to both
  existing and new instances." do
    GuineaPig = Class.new
    pig = GuineaPig.new
    class GuineaPig
      define_method :next_integer do
        @count = (@count || 0) + 1
      end
    end
    
    assert_equal 1, pig.next_integer
    assert_equal 2, pig.next_integer
    assert_equal 1, GuineaPig.new.next_integer
  end
=begin
This isn't all that cool, as we could have defined next_integer using the def
keyword. But Module#define_method allows us to do a couple of things the def
keyword doesn't. 

First, we can define our method name dynamically. Module#define_method takes a
symbol or string as the method name, whereas the method name following the def
keyword must be spelled out literally. You can satisfy this by evaluating a
string of Ruby code that defines the method using def, but I usually find this
less readable than using define_method. Try them both and see which reads better
in your context.

The second interesting aspect of using define_method is that you pass it a
block, Ruby's closure.
=end
  show "Method bodies created with define_method can reference the context in
  which they were created." do
    GuineaCounter = Class.new
    shared_count = 0 # A new local variable.
    GuineaCounter.send :define_method, :double_count do
      shared_count += 1
      @count ||= 0
      @count += 1
      [shared_count, @count]
    end
    first_counter = GuineaCounter.new
    second_counter = GuineaCounter.new
    
    assert_equal [1, 1], first_counter.double_count
    assert_equal [2, 2], first_counter.double_count
    assert_equal [3, 1], second_counter.double_count
    assert_equal [4, 2], second_counter.double_count
  end
=begin
Even if the method that defined the local variable shared_count completed
execution, the method in GuineaCounter will still be bound to the context of the
method. (This binding isn't simple, as the block also assigns instance variables
which obviously land in the right place. Look for a forthcoming write-up
exploring this in depth.)

Note the use of Object#send to invoke define_method, where we just reopened the
class in earlier demonstrations. This is necessary if we want the block to bind
to our local context. As mentioned earlier, I prefer module_eval or class_eval
for this, but I'm leaving those out of this article.

This next one may seem obvious, but it'll only take a moment.
=end
  show "Sending define_method to a module is consistent with sending it to a
  class." do
    o = Object.new.extend(Enumerable)
    # Object#extend mixes a module into an instance without affecting other 
    # instances of the same class.
    
    assert(o.is_a?(Enumerable) && {}.is_a?(Enumerable))
    
    hash = {}
    Enumerable.send :define_method, :next_integer_for_enumerables do
      @count_for_enumerables = (@count_for_enumerables || 0) + 1
    end
    
    assert_equal 1, o.next_integer_for_enumerables
    assert_equal 1, hash.next_integer_for_enumerables
    assert_equal 2, hash.next_integer_for_enumerables
    assert_equal 1, Array.new.next_integer_for_enumerables
    # But since we only extended that one instance of Object up above ...
    assert_raises(NoMethodError) { Object.new.next_integer_for_enumerables }
  end
=begin
This next point is something of a tangent, but it's important to keep in mind,
as it could bite you at some point.
=end
  show "Remember that adding methods to Object puts them all over the place, so
  be careful!" do
    o = Object.new
    Object.send :define_method, :next_integer_for_all do
      @count_for_all = (@count_for_all || 0) + 1
    end
    
    # So obviously, ...
    assert_equal 1, o.next_integer_for_all
    assert_equal 2, o.next_integer_for_all
    
    # But we also now have the method in this Test::Unit::TestCase.
    assert_nil @count_for_all
    assert_equal 1, next_integer_for_all
    assert_equal 1, @count_for_all
    
    # Classes are Objects too, so they've all gained a class method, which
    # maintains a count independent from its instances.
    assert_equal 1, String.next_integer_for_all
    assert_equal 2, String.next_integer_for_all
    assert_equal 1, "".next_integer_for_all
  end
=begin doc
This isn't mind-blowing, but it can be easy to accidentally call the method with
the wrong receiver if you lose track of your current context.

The takeaways from that are: 
 * don't add methods to Object unless you've got a damn good reason, and
 * prove that you're getting the desired behavior with tests.

Now here's where the cool stuff starts! Let's talk about singleton methods and
classes.

Above, we used Object#extend to mix a module into one instance of Object without
affecting other instances or the Object class itself. You've probably also seen
that Ruby allows you to define methods on just single instances. When done the
simple way, this looks like the following:
=end
  show "Methods can be defined on single instances using the def keyword.
  These are referred to as 'singleton methods.'" do
    o, p = Object.new, Object.new
    
    def o.say_hi
      'hello there'
    end
    
    assert_equal 'hello there', o.say_hi
    assert_raises(NoMethodError) { p.say_hi }
    assert_equal ['say_hi'], o.singleton_methods
    assert_true p.singleton_methods.empty?
  end
=begin
So that's neat, but what if we want some of the power of Module#define_method
discussed earlier? What module or class should define_method to add a method to
just one object? The singleton class!

Classes and Modules are special objects that can hold methods for other objects
to respond to. It would have been a shame for Matz to have had to implement
another sort of method owning facility to handle singleton methods, so Ruby does
some hidden trickery when we define a method on an instance: it creates a
virtual class to hold methods specific to that object, inserting it into the
chain of classes that will be checked for methods when it's looking to handle a
message sent to the object. The object's class method will still return the
original class, but the singleton class actually gets "first dibs" at responding
to a call. These classes are hidden from ObjectSpace and created without calling
Class.new, making them hard to get a hold of.

What do we call these things? The term 'singleton class' makes some sense, as
there's only one per object. This name can be confusing though, because of the
Singleton design pattern (easily implemented in Ruby by including the stdlib
module Singleton). The term 'metaclass' is used frequently, but it comes from
other languages and really applies only to the class of a class. Matz is
considering calling singleton classes 'eigenclasses' in future versions of Ruby
to reduce confusion with other concepts. (Chances are you don't have a
preconceived notion of what 'eigenclass' ought to mean, so there's nothing to
get mixed up with these funny classes in Ruby.) I'll continue to refer to these
as 'singleton classes' for now.

How unusual is it for singleton classes to come into play? It happens far more
frequently than we think about them, because all class methods are actually
singleton methods of instances of Class. Here's a simple class with a couple
class methods.
=end
  class Greeter
    def greet; 'hello!'; end
    
    def self.describe_greeting
      'Mostly it''s just saying hello to people.'
    end
  end
  
  def Greeter.say_more
    'Actually, saying hello pretty much covers it.'
  end
=begin
Notice how similar the second and third method definitions look to our singleton
method definition above. That's not a coincidence: describe_greeting and
say_more are both singleton methods of the object Greeter, an instance of the
class Class. These methods are both held in Greeter's singleton class, the first
place Ruby looks for methods when Greeter receives a message.
=end
  show "So-called 'class methods' are really just singleton methods of
  instances of Class." do
    assert_equal ['describe_greeting', 'say_more'].sort, Greeter.singleton_methods.sort
  end
=begin
Once you digest it, this hidden consistency makes it much easier to keep track
of what's going on in Ruby.

Now, we said above that singleton classes are hidden. How do we get at them?
Ruby gives us just one way in: the "class double-ell." Let's use this to add a
singleton method to a Greeter.
=end
  show "The 'class double-ell' gets us into the definition of an object's
  singleton class." do
    jim, jane = Greeter.new, Greeter.new
    class << jim
      def greet_enthusiastically
        self.greet.upcase
      end
    end
    
    assert_equal 'HELLO!', jim.greet_enthusiastically
    assert_raises(NoMethodError) { jane.greet_enthusiastically }
  end
=begin
This is also a third way (besides the two we saw above) to create class methods.
It's the only one that allows Ruby's visibility modifiers to work the way
they're normally used for instance methods (where they look like keywords even
though they're really method calls).
=end
  show "The 'class double-ell' can be used to create non-public class methods." do
    class Greeter
      class << self
        private
        def secret_truth
          'Greeting gets old fast!'
        end
        public
        def truth
          secret_truth.gsub /old fast/, 'better with every passing year'
        end
      end
    end
    assert_raises(NoMethodError) { Greeter.secret_truth } # because it's private
    assert_equal 'Greeting gets better with every passing year!', Greeter.truth
  end
=begin
Now let's make these singleton classes easier to get to. We create an instance
method on Object that returns the receiver's singleton class. I use the
convention of calling this method 'metaclass,' even though it's a poor name for
reasons already discussed.
=end
  class ::Object 
    def metaclass
      class << self
        self
      end
    end
  end
  
  show "The singleton class is a class, but not the same one returned by the
  Object#class method." do
    hash = Hash.new
    
    assert_true hash.metaclass.is_a?(Class)
    assert_false hash.class == hash.metaclass
  end
  
  show "Our method returns the same object on repeated calls to the same
  receiver." do
    hash = {}
    
    assert_same hash.metaclass, hash.metaclass
  end
  
  show "Instances do not share the same singleton class instance." do
    assert_not_same({}.metaclass, {}.metaclass)
  end
  
=begin
I'd also like to demonstrate here that an object doesn't have a singleton class
until it's actually needed, but I can't think of a way to do that given the
hiding discussed earlier.

Get ready for a mouthful.
=end
  show "The singleton class instance of a class is the superclass of the
  singleton class instances of instances of that class.  Phew!" do
    assert_same( {}.metaclass.superclass, Hash.metaclass)
  end
=begin
I can't think of any reason that's useful, but there it is.  The same goes for
singleton classes of classes (true metaclasses).
=end
  show "Same diff when the instance in question is a class." do
    assert_same Hash.metaclass.superclass, Class.metaclass
  end
  
  show "Bizarrely, same diff even when the instance in question is Class 
  itself!" do
    assert_same Class.metaclass.superclass, Class.metaclass
  end
=begin
Right this moment, it appears the inheritance chain of singleton classes may
change in the next version of Ruby. See this relatively awesome distillation of
changes in play for Ruby 1.9:
  http://eigenclass.org/hiki.rb?Changes+in+Ruby+1.9

Anyway, back to what we were trying to do: use Module#define_method to create a
singleton method.
=end
  show "Calling define method on a singleton class creates a singleton 
  method." do
    o = Object.new
    
    assert_equal 0, o.singleton_methods.size
    
    o.metaclass.send :define_method, :countdown do
      (@numbers ||= (1..3).to_a.reverse.push('POW!')).shift
    end
    
    assert_equal ['countdown'], o.singleton_methods
    assert_raises(NoMethodError) { Object.new.countdown }
    assert_equal 3, o.countdown
    assert_equal 2, o.countdown
    assert_equal 1, o.countdown
    assert_equal 'POW!', o.countdown
  end
=begin
I'm surprised that Matz didn't put a method on Object called
define_singleton_method, allowing us to do the same thing we did above without
exposing singleton classes. To me they feel like an implementation detail we
shouldn't have needed to see.

Let's create that method now.
=end
  class ::Object
    def define_singleton_method name, &body
      singleton_class = class << self; self; end
      singleton_class.send(:define_method, name, &body)
    end
  end
=begin
This is functionally equivalent to _why's meta_def method, but that name bugs
me a lot, so I'm not using it.
=end
  show "Use of our newly created Object#define_singleton_method to create a
  singleton method without ever seeing the singleton class." do
    o = Object.new
    o.define_singleton_method :get_excited do
      @excitation_rant = (@excitation_rant || "I'm getting excited.").gsub(/excited/, "really excited")
    end
    
    assert_equal "I'm getting really excited.", o.get_excited
    assert_equal "I'm getting really really excited.", o.get_excited
    assert_equal "I'm getting really really really excited.", o.get_excited
  end
=begin
With the ability to dynamically define methods on classes and instances at
runtime, you have the tools needed for some pretty interesting metaprogramming.
Have fun with it, just keep an eye on the developers around you to see if you're
going too meta on them.

---

If you have any comments, questions, suggestions, corrections, or additions for
this write-up, please leave comments on Practical Ruby
(http://practicalruby.blogspot.com/).

Thanks to a whole bunch of people for useful feedback, particularly: Jay Fields,
Z, Chris George, Ali Aghereza, and Omar Ghaffar.
=end
end
