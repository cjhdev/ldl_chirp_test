require 'minitest'
require "minitest/spec"
require 'ldl'

describe "otaa join nonce filter" do

    region = :EU_863_870

    describe(region) do

      let(:cycle_time){10}    # average time it takes to do otaa tx+rx cycle
      let(:dither){0}

      describe "complete OTAA when initial joinNonce is 0" do

        let(:join_nonce){ 0 }

        let(:scenario){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: dither, port: $port, join_nonce: join_nonce) }

        before do

          $cs.add_scenario(scenario)
          scenario.start
          scenario.device.unlimited_duty_cycle = true

        end

        after do

          scenario.stop
          $cs.remove_scenario(scenario)

        end

        it "shall succeed" do

          scenario.device.otaa(timeout: dither + cycle_time)

        end

      end

      describe "OTAA timeout when initial joinNonce is 1" do

        let(:join_nonce){ 1 }

        let(:scenario){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: dither, port: $port, join_nonce: join_nonce) }

        before do

          $cs.add_scenario(scenario)
          scenario.start
          scenario.device.unlimited_duty_cycle = true

        end

        after do

          scenario.stop
          $cs.remove_scenario(scenario)

        end

        it "shall timeout" do

          assert_raises ThreadError do
            scenario.device.otaa(timeout: dither + cycle_time)
          end

        end

      end

    end

end
