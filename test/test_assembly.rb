#! /usr/bin/ruby

require 'test/unit'
require 'cascading/assembly'

def compare_with_references(test_name)
  result = compare_files("test/references/#{test_name}.txt", "output/#{test_name}/part-00000")
  assert_nil(result)
end

class TC_Assembly < Test::Unit::TestCase

  include Cascading::Operations

  def mock_assembly(&block)
    Cascading::Flow.new 'test' do
      source 'test', tap('test/data/data1.txt')

      $assembly = assembly 'test' do
        instance_eval(&block)
      end
    end
    $assembly
  end

  def test_create_assembly_simple
    assembly = Cascading::Assembly.new("assembly1") do
    end

    assert_not_nil Cascading::Assembly.get("assembly1")
    assert_equal assembly, Cascading::Assembly.get("assembly1")
    pipe = assembly.tail_pipe
    assert pipe.is_a? Java::CascadingPipe::Pipe
  end

  def test_each_identity
    assembly = mock_assembly do
      each 'offset', :filter => identity
    end

    assert_not_nil Cascading::Assembly.get('test')
    assert_equal assembly, Cascading::Assembly.get('test')
  end

  def test_create_each  
    # You can't apply an Each to 0 fields
    assert_raise CascadingException do
      assembly = mock_assembly do
        each(:filter => identity)
      end
      assert assembly.tail_pipe.is_a? Java::CascadingPipe::Each
    end

    assembly = mock_assembly do
      each('offset', :output => 'offset_copy',
           :filter => Java::CascadingOperation::Identity.new(fields('offset_copy')))
    end
    pipe = assembly.tail_pipe

    assert pipe.is_a? Java::CascadingPipe::Each

    assert_equal 'offset', pipe.getArgumentSelector().get(0)
    assert_equal 'offset_copy', pipe.getOutputSelector().get(0)
  end

  # For now, replaced these tests with the trivial observation that you can't
  # follow a Tap with an Every.  Eventually, should support testing within a
  # group_by block.
  def test_create_every
    assert_raise CascadingException do
      assembly = mock_assembly do
        every(:aggregator => count_function)
      end
      pipe = assembly.tail_pipe
      assert pipe.is_a? Java::CascadingPipe::Every
    end

    assert_raise CascadingException do
      assembly = mock_assembly do
        every(:aggregator => count_function("field1", "field2"))
      end
      assert assembly.tail_pipe.is_a? Java::CascadingPipe::Every
    end

    assert_raise CascadingException do
      assembly = mock_assembly do
        every("Field1", :aggregator => count_function)
      end
      assert assembly.tail_pipe.is_a? Java::CascadingPipe::Every
      assert_equal "Field1", assembly.tail_pipe.getArgumentSelector().get(0)
    end

    assert_raise CascadingException do
      assembly = mock_assembly do
        every('line', :aggregator => count_function, :output=>'line_count')
      end
      assert assembly.tail_pipe.is_a? Java::CascadingPipe::Every
      assert_equal 'line', assembly.tail_pipe.getArgumentSelector().get(0)
      assert_equal 'line_count', assembly.tail_pipe.getOutputSelector().get(0)
    end
  end

  def test_create_group_by
    assembly = mock_assembly do
      group_by('line')
    end

    assert assembly.tail_pipe.is_a? Java::CascadingPipe::GroupBy
    grouping_fields = assembly.tail_pipe.getGroupingSelectors()['test']
    assert_equal 'line', grouping_fields.get(0) 

    assembly = mock_assembly do
      group_by('line')
    end

    assert assembly.tail_pipe.is_a? Java::CascadingPipe::GroupBy
    grouping_fields = assembly.tail_pipe.getGroupingSelectors()['test']
    assert_equal 'line', grouping_fields.get(0)
  end

  def test_create_group_by_many_fields
    assembly = mock_assembly do
      group_by(['offset', 'line'])
    end

    assert assembly.tail_pipe.is_a? Java::CascadingPipe::GroupBy
    grouping_fields = assembly.tail_pipe.getGroupingSelectors()['test']
    assert_equal 'offset', grouping_fields.get(0)
    assert_equal 'line', grouping_fields.get(1)
  end

  def test_create_group_by_with_sort
    assembly = mock_assembly do
      group_by('offset', 'line', :sort_by => ['line'])
    end

    assert assembly.tail_pipe.is_a? Java::CascadingPipe::GroupBy
    grouping_fields = assembly.tail_pipe.getGroupingSelectors()['test']
    sorting_fields = assembly.tail_pipe.getSortingSelectors()['test']

    assert_equal 2, grouping_fields.size
    assert_equal 1, sorting_fields.size

    assert_equal 'offset', grouping_fields.get(0)
    assert_equal 'line', grouping_fields.get(1)
    assert assembly.tail_pipe.isSorted()
    assert !assembly.tail_pipe.isSortReversed()
    assert_equal 'line', sorting_fields.get(0)
  end

  def test_create_group_by_with_sort_reverse
    assembly = mock_assembly do
      group_by('offset', 'line', :sort_by => ['line'], :reverse => true)
    end

    assert assembly.tail_pipe.is_a? Java::CascadingPipe::GroupBy
    grouping_fields = assembly.tail_pipe.getGroupingSelectors()['test']
    sorting_fields = assembly.tail_pipe.getSortingSelectors()['test']

    assert_equal 2, grouping_fields.size
    assert_equal 1, sorting_fields.size

    assert_equal 'offset', grouping_fields.get(0)
    assert_equal 'line', grouping_fields.get(1)
    assert assembly.tail_pipe.isSorted()
    assert assembly.tail_pipe.isSortReversed()
    assert_equal 'line', sorting_fields.get(0)
  end

  def test_create_group_by_reverse
    assembly = mock_assembly do
      group_by('offset', 'line', :reverse => true)
    end

    assert assembly.tail_pipe.is_a? Java::CascadingPipe::GroupBy
    grouping_fields = assembly.tail_pipe.getGroupingSelectors()['test']
    sorting_fields = assembly.tail_pipe.getSortingSelectors()['test']

    assert_equal 2, grouping_fields.size
    assert_equal 2, sorting_fields.size

    assert_equal 'offset', grouping_fields.get(0)
    assert_equal 'line', grouping_fields.get(1)
    assert assembly.tail_pipe.isSorted()
    assert assembly.tail_pipe.isSortReversed()
    assert_equal 'offset', sorting_fields.get(0)
    assert_equal 'line', sorting_fields.get(1)
  end

  def test_branch_unique
    assembly = mock_assembly do
      branch 'branch1'
    end

    assert_equal 1, assembly.children.size

  end

  def test_branch_empty
    assembly = mock_assembly do
      branch 'branch1' do
      end

      branch 'branch2' do
        branch 'branch3'
      end
    end

    assert_equal 2, assembly.children.size
    assert_equal 1, assembly.children[1].children.size

  end

  def test_branch_single
    assembly = mock_assembly do
      branch 'branch1' do
        branch 'branch2' do
          each 'line', :function => identity
        end
      end
    end

    assert_equal 1, assembly.children.size
    assert_equal 1, assembly.children[0].children.size

  end

  # Fixed this test, but it isn't even valid.  You shouldn't be able to follow
  # an Each with an Every.
  def test_full_assembly
    assert_raise CascadingException do
      assembly = mock_assembly do
        each('offset', :output => 'offset_copy',
             :filter => Java::CascadingOperation::Identity.new(fields('offset_copy')))
        every(:aggregator => count_function)
      end

      pipe = assembly.tail_pipe

      assert pipe.is_a? Java::CascadingPipe::Every
    end
  end

end


class TC_AssemblyScenarii < Test::Unit::TestCase

  def test_splitter
    flow = Cascading::Flow.new("splitter") do

      source "copy", tap("test/data/data1.txt")
      sink "copy", tap('output/splitter', :sink_mode => :replace)

      assembly "copy" do

        split "line", :pattern => /[.,]*\s+/, :into=>["name", "score1", "score2", "id"], :output => ["name", "score1", "score2", "id"]

        assert_size_equals 4

        assert_not_null

        debug :print_fields=>true
      end
    end
    # Had to wrap this in a CascadingException so that I could see the message
    # of the deepest cause -- which told me the output already existed.
    #
    # We can safely wrap all calls to Cascading in CE once we change it to
    # print the stack trace of -every- exception in the cause chain (otherwise
    # it eats the stack trace and you can't dig down into the Cascading code).
    begin
      flow.complete
    rescue NativeException => e
      throw CascadingException.new(e, 'Flow failed to complete')
    end
  end


  def test_join1
    flow = Cascading::Flow.new("splitter") do

      source "data1", tap("test/data/data1.txt")
      source "data2", tap("test/data/data2.txt")
      sink "joined", tap('output/joined', :sink_mode => :replace)

      assembly1 = assembly "data1" do

        split "line", :pattern => /[.,]*\s+/, :into=>["name", "score1", "score2", "id"], :output => ["name", "score1", "score2", "id"]
        
        assert_size_equals 4

        assert_not_null
        debug :print_fields=>true

      end

      assembly2 = assembly "data2" do

        split "line", :pattern => /[.,]*\s+/, :into=>["name",  "id", "town"], :output => ["name",  "id", "town"]

        assert_size_equals 3

        assert_not_null
        debug :print_fields=>true
      end

      assembly "joined" do
        join assembly1, assembly2, :on => ["name", "id"], :declared_fields => ["name", "score1", "score2", "id", "name2", "id2", "town"]
      
        assert_size_equals 7

        assert_not_null
        
      end
    end
    flow.complete
  end
  
  def test_join2
     flow = Cascading::Flow.new("splitter") do

       source "data1", tap("test/data/data1.txt")
       source "data2", tap("test/data/data2.txt")
       sink "joined", tap('output/joined', :sink_mode => :replace)

       assembly "data1" do

         split "line", :pattern => /[.,]*\s+/, :into=>["name", "score1", "score2", "id"], :output => ["name", "score1", "score2", "id"]

         debug :print_fields=>true

       end

       assembly "data2" do

         split "line", :pattern => /[.,]*\s+/, :into=>["name",  "code", "town"], :output => ["name",  "code", "town"]

         debug :print_fields=>true
       end

       assembly "joined" do
         join :on => {"data1"=>["name", "id"], "data2"=>["name", "code"]}, :declared_fields => ["name", "score1", "score2", "id", "name2", "code", "town"]
       end
     end
    begin
      flow.complete
    rescue NativeException => e
      throw CascadingException.new(e, 'Flow failed to complete')
    end
   end
end
