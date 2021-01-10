require 'minitest'
require "minitest/spec"
require 'ldl'

describe "otaa" do

  $regions.each do |region|

    describe(region) do

      let(:cycle_time){9}    # average time it takes to do otaa tx+rx cycle
      let(:dither){10}
      let(:scenario){ LDL::Scenario.new(logger: $logger, otaa_dither: dither, region: region) }

      before do

        $cs.add_scenario(scenario)
        scenario.start

      end

      after do

        scenario.stop
        $cs.remove_scenario(scenario)

      end

      describe "perfect reception" do

        it "shall complete on first attempt" do
          scenario.device.otaa(timeout: dither + cycle_time)
        end

      end

      describe "timeout waiting to join" do

        before do
          scenario.device.reliability = 0
        end

        after do
          scenario.device.reliability = nil
        end

        it "raises thread error to timeout" do
          assert_raises ThreadError do
            scenario.device.otaa(timeout: dither + cycle_time)
          end
        end

      end

      describe "fail multiple attempts before succeeding" do

        let(:attempts){[0,0,0,1]}

        before do
          skip if scenario.region == :US_902_928
          scenario.device.reliability = attempts.dup
        end

        after do
          scenario.device.reliability = nil
        end

        it "shall retry until successful" do
          scenario.device.otaa(timeout: (attempts.size*(dither + cycle_time + 10)))
        end

      end

    end

  end

end
