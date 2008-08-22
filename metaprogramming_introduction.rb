require 'rubygems'
gem 'rspec'
require 'spec'

describe "Ruby Metaprogramming" do

=begin

This is a demonstration of the basic Ruby functionality used in metaprogramming.
It will cover dynamic method definition using Module#define_method, look at
singleton classes (also known as metaclasses), and demonstrate use of class
methods as macros.

Note that I'm going to avoid use or discussion of Ruby's very important eval
methods in this article. This is only to reduce the scope of what's explained.
In practice I'd prefer module_eval or class_eval to reopening of classes or
modules or use of Object#send to invoke private methods.

Chapter 24 in the Pickaxe is a good reference for the nuts and bolts of Ruby
classes. There's surprisingly little discussion of things you can do with
metaprogramming, but all the information you need is there. _why the lucky
stiff's Seeing Metaclasses Clearly is dense and opaque, but fun:
  http://whytheluckystiff.net/articles/seeingMetaclassesClearly.html

=end
  describe "using Module#define_method" do
    it "allows you to add an instance method to both new and existing instances of the receiving module" do
      GuineaPig = Class.new
      pig = GuineaPig.new
      class GuineaPig
        define_method :next_integer do
          @count = (@count || 0) + 1
        end
      end
    
      pig.next_integer.should == 1
      pig.next_integer.should == 2
      GuineaPig.new.next_integer.should == 1
    end
=begin

That's nothing special, since we could have defined next_integer using the def
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
    it "allows method bodies to close over local variables" do
      GuineaCounter = Class.new
      shared_count = 0 # A new local variable.
      GuineaCounter.class_eval do
        define_method :double_count do
          shared_count += 1
          @count ||= 0
          @count += 1
          [shared_count, @count]
        end
      end
      first_counter = GuineaCounter.new
      second_counter = GuineaCounter.new
    
      first_counter.double_count.should  == [1, 1]
      first_counter.double_count.should  == [2, 2]
      second_counter.double_count.should == [3, 1]
      second_counter.double_count.should == [4, 2]
    end
=begin

Even after the method that defined the local variable shared_count completes
execution, the method in GuineaCounter will still be bound to the context of the
method, which lives on thanks to those bindings. 

Note that the binding to local variables is independent of the value of self when
the method is executed (and therefore the object where instance variables are
stored). This can be confusing, since the code in that block doesn't quite work
like code defined in a normal method (e.g., it can see and reassign the local
shared_count variable from the surrounding local binding) but doesn't quite work
like normal "local" code (e.g., when it sets the @count instance variable, the
variable lands in the receiver of the method).

Note the use of Module#class_eval (alias Module#module_eval) to invoke
define_method, where we just reopened the class in earlier demonstrations. This is
necessary if we want the block to bind to the surrounding context. (Use of the class
keyword to define or reopen a class establishes a whole new binding.) You can also
use Object#send, but I always prefer class_eval.

This next one may seem obvious, but it'll only take a moment.

=end
    it "works the same way with modules as it does with classes" do
      o = Object.new.extend(Enumerable)
      # Object#extend mixes a module into an instance without affecting other 
      # instances of the same class.
    
      o.should be_a_kind_of(Enumerable)
    
      hash = {}
      Enumerable.class_eval do
        define_method :next_integer_for_enumerables do
          @count_for_enumerables = (@count_for_enumerables || 0) + 1
        end
      end
    
      o.next_integer_for_enumerables.should == 1
      hash.next_integer_for_enumerables.should == 1
      hash.next_integer_for_enumerables.should == 2
      Array.new.next_integer_for_enumerables.should == 1
      # But since we only extended that one instance of Object up above ...
      lambda { Object.new.next_integer_for_enumerables }.should raise_error(NoMethodError)
    end
  end
=begin

This next point is something of a tangent, but it's important to keep in mind,
as it could bite you at some point.

=end
  describe "adding methods to Object" do
    it "makes them available on EVERY receiver, so be careful" do
      Object.class_eval do
        define_method :next_integer_for_all do
          @count_for_all = (@count_for_all || 0) + 1
        end
      end
      o = Object.new
    
      # So obviously, ...
      o.next_integer_for_all.should == 1
      o.next_integer_for_all.should == 2
      
      # But we also now have the method in this spec.
      @count_for_all.should be_nil
      next_integer_for_all.should == 1
      @count_for_all.should == 1
      
      # Classes are Objects too, so they've all gained a class method, which
      # maintains a count independent from its instances.
      String.next_integer_for_all.should == 1
      String.next_integer_for_all.should == 2
      "".next_integer_for_all.should == 1
    end
  end
=begin

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
  describe "basic singleton method definition" do
    it "uses the def keyword to create methods on object instances" do
      o, p = Object.new, Object.new
      
      def o.say_hi
        'hello there'
      end
    
      o.say_hi.should == 'hello there'
      lambda { p.say_hi }.should raise_error(NoMethodError)
      o.singleton_methods.should == ['say_hi']
      p.singleton_methods.should be_empty
    end
  end
=begin

So that's neat, but what if we want some of the power of Module#define_method
discussed earlier? What module or class can we call define_method on to add a 
method to just one object? The singleton class!

So what's the singleton class?

Classes and Modules are special objects with method tables that hold methods for
other objects to respond to. It would have been a shame for Matz to have had to
implement another method table facility to support singleton methods, so Ruby does
some hidden trickery when we define a method on an instance: it creates a hidden
class to hold methods specific to that object, inserting it into the chain of
classes that will be checked for methods when it's looking to handle a message
sent to the object. The object's Object#class method will still return the
original class, but the singleton class actually gets "first dibs" at responding
to a message. These classes are hidden from ObjectSpace and created without
calling Class.new, making them hard to get a hold of.

Some readers might find it easier to think about singleton classes in more
biological and psychological terms. There's a sort of silly Nature-vs-Nurture
comparison to be made: 

  An object's class is like its DNA: the behavior it's born with. Its singleton
  class is like the maleable brain matter that can learn new behavior over the
  course of the object's lifetime.

Cheesy people sometimes say that certain objects (cars, homes, guitars) have a
certain soul to them ... something ineffable and irrecreatable that makes these
objects different from others. If the world is like the JVM, that's just not
possible. But if the world is like a Ruby interpreter, objects do can have souls!

Why do we call these things 'singleton classes'? First, the term makes some sense, as
there's only one per object. This name can be confusing though, because of the
Singleton design pattern (easily implemented in Ruby by including the stdlib
module Singleton). The term 'metaclass' is used frequently, but it comes from
other languages and really applies only to the class of a class. Matz is
considering calling singleton classes 'eigenclasses' in future versions of Ruby
to reduce confusion with other concepts. (Chances are you don't have a
preconceived notion of what 'eigenclass' ought to mean.) I'll continue to refer to these
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
  describe "A class method" do
    it "is really just a singleton method of an instances of Class" do
      Greeter.singleton_methods.should include('describe_greeting', 'say_more')
    end
  end
=begin

Once you digest it, this hidden consistency makes it much easier to keep track
of what's going on in Ruby.

Now, we said above that singleton classes are hidden. How do we get at them?
Ruby gives us just one way in: the "class double-ell." Let's use this to add 
a singleton method to a Greeter.

=end
  describe "'class double-ell'" do
    it "gets us into the definition of an object's singleton class" do
      jim, jane = Greeter.new, Greeter.new
      class << jim
        def greet_enthusiastically
          self.greet.upcase
        end
      end
    
      jim.greet_enthusiastically.should == 'HELLO!'
      lambda { jane.greet_enthusiastically }.should raise_error(NoMethodError)
    end
=begin

I recommend you read "class << X" as "opening the singleton class of X...".

(Ruby generates singleton classes on demand, so each object gets one just as soon
as you want to use it. You may read or hear people say that every object has a 
singleton class. Though it's not strictly true (since in principle it's turtles 
all the way down), it's practically true, since Ruby makes sure you can't ever 
look for a singleton class and not find it.) 

So "class << self" is a third way to create class methods.

It's the only one that allows Ruby's visibility modifiers to work the way
they're normally used for instance methods (annotation-style).

=end
    it "can be used to create non-public class methods" do
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
      lambda { Greeter.secret_truth }.should raise_error(NoMethodError) # because it's private
      Greeter.truth.should == 'Greeting gets better with every passing year!'
    end
  end
=begin

Now let's make these singleton classes easier to get to. We'll create an instance
method on Object that returns the receiver's singleton class, then dig in with some examples about how they work.

=end
  class Object 
    def singleton_class
      class << self
        self
      end
    end
  end

  describe "The singleton class" do
    it "is a class, but not the same class returned by the Object#class method" do
      hash = Hash.new
    
      hash.singleton_class.should be_an_instance_of(Class)
      hash.singleton_class.should_not == hash.class
    end
    
    it "is not shared by instances" do
      {}.singleton_class.should_not == {}.singleton_class
    end
  end
=begin

Anyway, back to what we were trying to do: use Module#define_method to create a
singleton method.

=end
  specify "Calling define method on a singleton class creates a singleton method." do
    o = Object.new
    
    o.singleton_methods.should be_empty
    
    o.singleton_class.send :define_method, :countdown do
      (@numbers ||= [3, 2, 1, 'POW!']).shift
    end
    
    o.singleton_methods.should == ['countdown']
    lambda { Object.new.countdown }.should raise_error(NoMethodError)
    o.countdown.should == 3
    o.countdown.should == 2
    o.countdown.should == 1
    o.countdown.should == 'POW!'
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
  specify "Use of our newly created Object#define_singleton_method to create a
  singleton method without ever seeing the singleton class." do
    o = Object.new
    o.define_singleton_method :get_excited do
      @excitation_rant = (@excitation_rant || "I'm getting excited.").gsub(/excited/, "really excited")
    end
    
    o.get_excited.should == "I'm getting really excited."
    o.get_excited.should == "I'm getting really really excited."
    o.get_excited.should == "I'm getting really really really excited."
  end
=begin

Now we know how to conveniently and dynamically define methods on classes and instances
at runtime. How can we use that to do something powerful? The most common case of
metaprogramming the Rubyist runs into on a daily basis is the use of class methods as
macros to define instance methods. For example:

  class Person
    attr_accessor :first_name, :last_name, :favorite_color
  end

That one call to #attr_accessor just generated six instance methods in Person. Although
attr_accessor is baked into Ruby (as an instance method of Module), it's not doing
anything we can't do ourselves. Rails' ActiveSupport, for example, adds similar methods
called mattr_accessor and cattr_accessor to Module and Class respectively. (They just 
read and write class variables instead of instance variables.)

So that's fine if we want to enhance every class or module under the sun with some new
macro, but chances are we don't. ActiveRecord, for example, exposes these great macros
for associations (has_one, has_many, belongs_to, etc), and it's sane enough to expose
them in your ActiveRecord::Base subclasses. So obviously the inheritance hierarchy is
taking care of this for us. Let's see what it looks like.

=end
  describe "#superclass on a singleton class" do
    it "returns the singleton class of the class the original object is an instance of" do
      {}.singleton_class.superclass.should == Hash.singleton_class
    end
=begin

That doesn't seem useful, but there it is.  But we're really after macros in classes, so
let's look at a singleton class of a class (a true metaclass).

=end
    it "works the same way when the instance in question is a class" do
      class Foo; end
      Foo.singleton_class.superclass.should == Class.singleton_class
      class Bar < Foo; end
      Bar.singleton_class.superclass.should == Class.singleton_class
    end
  end
=begin

WTF!? If B's singleton class's superclass is Class's singleton class instead of A's,
B isn't going to inherit class methods from A. So how does ActiveRecord make this work?

The answer is that the #superclass method is a damn dirty liar when the receiver is a
singleton class. In fact, B's singleton class's superclass really is A's singleton class.
(I should probably say "B's singleton class's super pointer really points at A's
singleton class.")

  Note: I believe Ruby 1.9 changes the behavior of the superclass method on singleton
  classes to reflect reality, but I haven't had a chance to look at it myself. You may 
  find helpful information here:
    http://eigenclass.org/hiki.rb?Changes+in+Ruby+1.9

Let's see some class methods get inherited.

=end
  describe "Inheritance of class methods" do
    it "works" do
      class A
        def self.say_hi; 'hi'; end
      end

      class B < A; end

      B.say_hi.should == 'hi'
    end
=begin

Because the subclass is the receiver, the inherited class method can write new instance
methods into the subclass.

=end
    it "allows you to define inherited macro methods" do
      class A
        def self.has_a_fondness_for *things
          things.each {|thing| define_method("fond_of_#{thing}?") { true } }
        end
      end
=begin

Note that the define_method call has self as the implicit receiver. So whatever subclass
is sent the has_a_fondness_for method, it will be the one that gets the defined instance
methods.

=end
      class B < A
        has_a_fondness_for :grapes, :granola, :guacamole
      end
      
      b = B.new
      b.fond_of_grapes?.should == true
      # or, in easier to read Rspec style,
      b.should be_fond_of_grapes
      b.should be_fond_of_granola
      b.should be_fond_of_guacamole
=begin

And just to be clear that the behavior lands only where we want it ...

=end
      class C < A
        has_a_fondness_for :cheese
      end
      
      c = C.new
      c.should be_fond_of_cheese
      lambda { c.fond_of_grapes? }.should raise_error(NoMethodError)
      lambda { b.fond_of_cheese? }.should raise_error(NoMethodError)
    end
  end
=begin

So that's a crash course in Ruby metaprogramming. Have fun with it, just keep an eye on 
the developers around you to see if you're going too meta on them.



---
If you have any comments, questions, suggestions, corrections, or additions for
this write-up, please contact me via my blog, http://elhumidor.blogspot.com/.

Thanks to a whole bunch of people for useful feedback, particularly: Jay Fields,
Z, Chris George, Ali Aghereza, and Omar Ghaffar.
=end
end
