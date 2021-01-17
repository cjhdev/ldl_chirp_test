require 'minitest'
require "minitest/spec"
require 'ldl'

describe "adr" do

    region = :EU_863_870

    describe(region) do

      let(:scenario){ LDL::Scenario.new(logger: $logger, otaa_dither: 0, region: region, port: $port) }

      let(:start_rate){0}
      let(:start_power){0}
      let(:trials){3}

      before do
        $cs.add_scenario(scenario)
        scenario.start
        scenario.device.unlimited_duty_cycle = true
        scenario.device.otaa(timeout: 30)
      end

      after do
        scenario.stop
        $cs.remove_scenario(scenario)
      end

      describe "adr enabled" do

        before do
          scenario.device.rate = start_rate
          assert_equal start_rate, scenario.device.rate
          assert_equal start_power, scenario.device.power
          assert scenario.device.adr
        end

        describe "unconfirmed" do

          it "reduces rate" do

            # chirpstack does this earlier
            trials.times do
              scenario.device.unconfirmed ""
              break if scenario.device.rate != start_rate
              break if scenario.device.power != start_power
            end

            assert scenario.device.rate != start_rate
            assert scenario.device.power != start_power

          end

        end

        describe "confirmed" do

          it "reduces rates" do

            trials.times do
              scenario.device.confirmed ""
              break if scenario.device.rate != start_rate
              break if scenario.device.power != start_power
            end

            assert scenario.device.rate != start_rate
            assert scenario.device.power != start_power

          end

        end

      end

      describe "adr disabled" do

        before do
            scenario.device.adr = false
            scenario.device.rate = start_rate
            assert_equal start_rate, scenario.device.rate
            assert_equal start_power, scenario.device.power
            refute scenario.device.adr
          end

        describe "unconfirmed" do

          it "does not reduce rate" do

            # chirpstack does this earlier
            trials.times do
              scenario.device.unconfirmed ""
              break if scenario.device.rate != start_rate
              break if scenario.device.power != start_power
            end

            assert scenario.device.rate == start_rate
            assert scenario.device.power == start_power

          end

        end

        describe "confirmed" do

          it "does not reduce rate" do

            trials.times do
              scenario.device.confirmed ""
              break if scenario.device.rate != start_rate
              break if scenario.device.power != start_power
            end

            assert scenario.device.rate == start_rate
            assert scenario.device.power == start_power

          end

        end

      end

    end

end



