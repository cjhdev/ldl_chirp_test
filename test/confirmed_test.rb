require 'minitest'
require "minitest/spec"
require 'ldl'

describe "confirmed" do

  let(:scenario){ LDL::Scenario.new(logger: $logger, otaa_dither: 0, region: $regions.sample) }

  before do

    $cs.add_scenario(scenario)
    scenario.start
    scenario.device.otaa(timeout: 30)

  end

  after do

    scenario.stop
    $cs.remove_scenario(scenario)

  end

  describe "perfect reception" do

    it "shall complete" do
      scenario.device.confirmed("hello world")
    end

  end

  describe "drop first attempt" do

    # ensure the next packet disappears
    before do
      scenario.device.reliability = [0]
    end

    after do
      scenario.device.reliability = nil
    end

    it "shall fail on first attempt" do
      assert_raises LDL::DataTimeout do
        scenario.device.confirmed("hello world")
      end
    end

    it "shall complete on second attempt" do
      scenario.device.confirmed("hello world", nbTrans: 2)
    end

  end

  describe "drop all attempts" do

    before do
      scenario.device.reliability = 0
    end

    after do
      scenario.device.reliability = nil
    end

    it "shall fail on first attempt" do
      assert_raises LDL::DataTimeout do
        scenario.device.confirmed("hello world")
      end
    end

    it "shall fail on multiple attempts" do
      assert_raises LDL::DataTimeout do
        scenario.device.confirmed("hello world", nbTrans: 3)
      end
    end

  end

end
