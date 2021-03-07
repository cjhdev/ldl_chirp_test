require 'minitest'
require "minitest/spec"
require 'ldl'

describe "otaa exhaustion" do

    region = :EU_863_870

    describe(region) do

      let(:cycle_time){10}    # average time it takes to do otaa tx+rx cycle
      let(:dither){0}

      describe "complete OTAA when devNonce is 65535" do

        let(:dev_nonce){ 65535 }

        let(:scenario){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: dither, port: $port, dev_nonce: dev_nonce) }

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

          assert_equal (dev_nonce+1), scenario.device.next_dev_nonce

        end

      end

      describe "fail before OTAA request when devNonce greater than 65535" do

        let(:dev_nonce){ 65536 }

        let(:scenario){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: dither, port: $port, dev_nonce: dev_nonce) }

        before do

          $cs.add_scenario(scenario)
          scenario.start
          scenario.device.unlimited_duty_cycle = true

        end

        after do

          scenario.stop
          $cs.remove_scenario(scenario)

        end

        it "shall raise exception immediately" do

          assert_equal dev_nonce, scenario.device.next_dev_nonce

          assert_raises LDL::ErrDevNonce do

            scenario.device.otaa(timeout: dither + cycle_time)

          end

        end

      end

      describe "fail during OTAA when devNonce increments past 65535" do

        let(:dev_nonce){ 65535 }

        let(:scenario){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: dither, port: $port, dev_nonce: dev_nonce) }

        before do

          $cs.add_scenario(scenario)
          scenario.start
          scenario.device.unlimited_duty_cycle = true
          scenario.device.reliability = [0,1]

        end

        after do

          scenario.stop
          $cs.remove_scenario(scenario)

        end

        it "shall raise exception on second attempt" do

          assert_raises LDL::ErrDevNonce do

            scenario.device.otaa(timeout: 2*(dither + cycle_time))

          end

        end

      end

    end

end
