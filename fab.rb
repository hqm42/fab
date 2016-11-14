class Dog
  attr_accessor :name, :age, :weight, :speed, :cat
end

class Cat
  attr_accessor :name, :food
end

class AttributesHashCollector
  attr_reader :attributes_hash

  def initialize
    @attributes_hash = {}
  end

  def method_missing(method_name, *args, &definition_block)
    @attributes_hash[method_name] =
      case definition_block.arity
      when 1 then definition_block.call(@attributes_hash)
      when 0 then definition_block.call
      else fail 'definition block must accept zero or one argument'
      end
  end
end

class MethodCallsRecorder
  def initialize(record_target)
    @record_target = record_target
  end

  def method_missing(m, *args, &block)
    @record_target << {
      method_name: m,
      args: args,
      block: block
    }
  end
end

class MethodCallsCollector
  attr_reader :method_calls

  def initialize(&block)
    @method_calls = []
    MethodCallsRecorder.new(@method_calls).instance_eval &block
  end
end

class FabMethodCallsCollector < MethodCallsCollector
  def initialize(&block)
    super(&block)
    duplicate_calls = method_calls.group_by { |method_name:, **_| method_name }.values.select {|calls| calls.length > 1}
    fail "duplicate call of #{duplicate_calls.map{|calls| calls.first[:method_name]}.join(', ')}" if duplicate_calls.any?
  end
end

class MethodCallsMerger
  attr_reader :method_calls
  def initialize(default_method_calls, overrides_method_calls)
    @method_calls = default_method_calls.reduce([[], overrides_method_calls]) do |(merged_method_calls, overrides_method_calls), default_call|
      override_candidate = overrides_method_calls.find { |call| call[:method_name] == default_call[:method_name]}
      if !override_candidate.nil?
        merged_method_calls = merged_method_calls + overrides_method_calls.take_while { |call| call != override_candidate }
        merged_method_calls << merge(default_call, override_candidate)
        overrides_method_calls = overrides_method_calls.drop_while { |call| call != override_candidate }.drop(1)
      else
        merged_method_calls += [default_call]
      end
      [merged_method_calls, overrides_method_calls]
    end.flatten
  end

  def merge(default_call, override_call)
    override_call
  end
end

class FabMethodCallsMerger < MethodCallsMerger
  def initialize(default_method_calls, overrides_method_calls)
    super
    duplicate_calls = method_calls.group_by { |method_name:, **_| method_name }.values.select {|calls| calls.length > 1}
    fail "unordered call of #{duplicate_calls.map{|calls| calls.first[:method_name]}.join(', ')}" if duplicate_calls.any?
  end
end

class Fab
  def initialize(clazz, parent: nil, &defaults_block)
    @clazz = clazz
    @defaults_block = defaults_block
    @parent = parent
  end

  def create(&overrides_block)
    attributes_collector = AttributesHashCollector.new
    apply_method_calls(attributes_collector, merge_method_calls(&overrides_block))
    attributes_hash = attributes_collector.attributes_hash

    assign_attributes_to_instance(attributes_hash, @class.new)
  end

  def assign_attributes_to_instance(attributes_hash, instance)
    attributes_hash.reduce(instance) do |instance, (attribute_name, value)|
      instance.public_send("#{attribute_name}=", value)
      instance
    end
  end

  def collect_method_calls(&block)
    FabMethodCallsCollector.new(&block).method_calls
  end

  def merge_method_calls(&overrides_block)
    if overrides_block.nil?
      own_method_calls
    else
      overrides_method_calls = collect_method_calls(&overrides_block)
      FabMethodCallsMerger.new(own_method_calls, overrides_method_calls).method_calls
    end
  end

  def own_method_calls
    own_calls = collect_method_calls(&@defaults_block)
    if @parent.nil?
      own_calls
    else
      FabMethodCallsMerger.new(@parent.own_method_calls, own_calls).method_calls
    end
  end

  def apply_method_calls(target, method_calls)
    method_calls.each do |method_call|
      p method_call
      target.public_send(method_call[:method_name], *method_call[:args], &method_call[:block])
    end
  end
end

def dogs
  dog_fab = Fab.new(Dog) do
    name { 'schnuffi' }
    age { 5 }
    weight { 10 }
    speed { |attrs| attrs[:weight] > 25 ? :slow : :fast }
  end

  dog_fab.create do
    name { 'fifi' }
    weight { 100 }
  end

  big_dog_fab = Fab.new(Dog, parent: dog_fab) do
    weight { 100 }
    speed { 1000 }
  end

  big_dog_fab.create do
    name { 'hasso' }
  end

  cat_fab = Fab.new(Cat) do
    name { 'mauzi' }
    food { 'fish' }
  end

  big_dog_with_cat_fab = Fab.new(Dog, parent: big_dog_fab) do
    cat do
      cat_fab.create do
        name { 'miez' }
      end
    end
  end

  big_dog_with_cat_fab.create
end
