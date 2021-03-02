require 'minitest'
require "minitest/spec"
require 'ldl'

describe "data size" do

  region = :EU_863_870

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

    describe "oversise payload" do

      let(:msg){ SecureRandom.bytes(255) }
      let(:port){ rand(1..100) }

      it "shall raise LDL_STATUS_SIZE" do

        assert_raises LDL::ErrSize do

          scenario.device.unconfirmed(port, msg)

        end

      end

    end

  end

end
