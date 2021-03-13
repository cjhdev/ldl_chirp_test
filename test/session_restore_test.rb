require 'minitest'
require "minitest/spec"
require 'ldl'

describe "session restore" do

  region = :EU_863_870

  describe(region) do

    describe "no session" do

      let(:scenario){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: 0, port: $port) }

      before do
        $cs.add_scenario(scenario)
        scenario.start
        scenario.device.unlimited_duty_cycle = true
      end

      after do
        scenario.stop
        $cs.remove_scenario(scenario)
      end

      it "returns nil" do

        assert_nil scenario.device.session

      end

    end

    describe "session returned after join" do

      let(:scenario){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: 0, port: $port) }

      before do
        $cs.add_scenario(scenario)
        scenario.start
        scenario.device.unlimited_duty_cycle = true
        scenario.device.otaa(timeout: 10)
      end

      after do
        scenario.stop
        $cs.remove_scenario(scenario)
      end

      it "returns session" do
        refute_nil scenario.device.session
      end

    end

    describe "session restored after join" do

      let(:scenario1){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: 0, port: $port) }
      let(:scenario2) do
        LDL::Scenario.new(
          logger: $logger,
          region: region,
          otaa_dither: 0,
          port: $port,
          gw_eui: scenario1.gw.eui,
          session: scenario1.device.session,
          dev_eui: scenario1.device.dev_eui,
          join_eui: scenario1.device.join_eui,
          dev_nonce: scenario1.device.next_dev_nonce,
          join_nonce: scenario1.device.join_nonce,
          app_key: scenario1.device.app_key,
          nwk_key: scenario1.device.nwk_key
        )
      end

      before do

        $cs.add_scenario(scenario1)

        scenario1.start
        scenario1.device.unlimited_duty_cycle = true
        scenario1.device.otaa(timeout: 10)
        scenario1.device.confirmed 1, "hello"
        scenario1.device.confirmed 1, "world"
        scenario1.stop

        scenario2.start
        scenario2.device.unlimited_duty_cycle = true

        assert_equal scenario1.device.dev_eui, scenario2.device.dev_eui
        assert_equal scenario1.device.join_eui, scenario2.device.join_eui
        assert_equal scenario1.device.next_dev_nonce, scenario2.device.next_dev_nonce
        assert_equal scenario1.device.join_nonce, scenario2.device.join_nonce

        assert_equal scenario1.device.app_key, scenario2.device.app_key
        assert_equal scenario1.device.nwk_key, scenario2.device.nwk_key
        assert_equal scenario1.device.keys[:apps], scenario2.device.keys[:apps]
        assert_equal scenario1.device.keys[:fnwksint], scenario2.device.keys[:fnwksint]

      end

      after do
        scenario2.stop
        $cs.remove_scenario(scenario1)
      end

      it "is already joined" do

        assert scenario2.device.joined

      end

      it "sends uplink normally" do

        scenario2.device.confirmed 1, "hello world"

      end

    end

  end

end
