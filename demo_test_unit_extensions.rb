require 'test/unit'

class Test::Unit::TestCase
  def self.show(name, &body)
    name.gsub!(/\n/, '')
    name.squeeze!(' ')
    puts "* #{name} (Line #{line_from(caller.first)})"
    define_method :"test #{name.gsub(/[[:punct:]]/,'')}", body
  end
  
  def assert_true expression
    assert_equal true, expression
  end
  
  def assert_false expression
    assert_equal false, expression
  end
  
  def self.line_from caller_line
    caller_line.split(':').last
  end
end