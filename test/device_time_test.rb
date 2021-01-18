require 'minitest'
require "minitest/spec"
require 'ldl'

describe "device time" do

  $regions.each do |region|

    #region = :EU_863_870

    let(:epoch){Time.new(1980,1,6).utc}
    let(:time_now){Time.now.utc}

    describe(region) do

      let(:scenario){ LDL::Scenario.new(logger: $logger, otaa_dither: 0, region: region, port: $port) }

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

      describe "get device time" do

        let(:result){ TimeoutQueue.new }

        before do
          scenario.device.on_device_time do |obj|
            result.push(obj)
          end
        end

        it "shall complete" do

          scenario.device.unconfirmed("", time: true)

          value = result.pop(timeout: 0)

          # need to account leap years
          #assert (time_now-1..time_now+1).include? (epoch + value[:seconds])

        end

      end

    end

  end

end
