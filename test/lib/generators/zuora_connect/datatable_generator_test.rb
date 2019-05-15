require 'test_helper'
require 'generators/datatable/datatable_generator'

module ZuoraConnect
  class DatatableGeneratorTest < Rails::Generators::TestCase
    tests DatatableGenerator
    destination Rails.root.join('tmp/generators')
    setup :prepare_destination

    # test "generator runs without errors" do
    #   assert_nothing_raised do
    #     run_generator ["arguments"]
    #   end
    # end
  end
end
