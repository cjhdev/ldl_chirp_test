require 'minitest'
require "minitest/spec"
require 'ldl'

describe "otaa" do

  $regions.each do |region|

    describe(region) do

      let(:cycle_time){10}    # average time it takes to do otaa tx+rx cycle
      let(:dither){0}
      let(:scenario){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: dither, port: $port) }

      before do

        $cs.add_scenario(scenario)
        scenario.start
        scenario.device.unlimited_duty_cycle = true

      end

      after do

        scenario.stop
        $cs.remove_scenario(scenario)

      end

      describe "perfect reception" do

        it "shall complete on first attempt" do

          scenario.device.otaa(timeout: dither + cycle_time)

          assert 1, scenario.device.next_dev_nonce

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

      describe "succeed on second attempt after join request lost" do

        let(:attempts){[0,1]}

        before do
          scenario.device.reliability = attempts.dup
        end

        after do
          scenario.device.reliability = nil
        end

        it "shall retry until successful" do

          scenario.device.otaa(timeout: (attempts.size*(dither + cycle_time)))

          assert 2, scenario.device.next_dev_nonce

        end

      end

      describe "succeed on second attempt after join accept lost" do

        let(:attempts){[0,1]}

        before do
          scenario.gw.reliability = attempts.dup
        end

        after do
          scenario.gw.reliability = nil
        end

        it "shall retry until successful" do

          scenario.device.otaa(timeout: (attempts.size*(dither + cycle_time)))

          assert 2, scenario.device.next_dev_nonce

        end

      end

    end

  end

end
