require 'chirpstack_api'
require 'securerandom'
require 'open3'

require_relative 'join_server'
require_relative 'app_server'

class ChirpStack

  NS = ChirpStackAPI::NS

  # magical barely documented address that maps to localhost from inside docker compose
  LOCALHOST = "172.17.0.1"

  AS_PORT = 8001
  JS_PORT = 8003

  COMPOSE_FILE = File.expand_path(File.join(File.dirname(__FILE__), "docker-compose.yml"))

  def self.run(**opts)

    inst = self.new(**opts)
    inst.start
    begin
      yield(inst) if block_given?
    rescue => e
      begin
        inst.stop
      rescue
      end
      raise e
    end
    inst.stop

  end

  def initialize(**opts)

    @logger = opts[:logger]||NULL_LOGGER
    @mutex = Mutex.new

    @stubs = {}

    @stubs[:EU_863_870] = NS::NetworkServerService::Stub.new('localhost:9000', :this_channel_is_insecure)
    @stubs[:US_902_928] = NS::NetworkServerService::Stub.new('localhost:9001', :this_channel_is_insecure)
    @stubs[:AU_915_928] = NS::NetworkServerService::Stub.new('localhost:9002', :this_channel_is_insecure)

    @js = JoinServer.new(logger: @logger, port: JS_PORT)

    @as = GRPC::RpcServer.new
    @as.add_http2_port("0.0.0.0:#{AS_PORT}", :this_port_is_insecure)
    @as.handle(AppServer.new)

    @pid = nil
    @stdin = nil
    @stdout = nil
    @waiter = nil

    @as_worker = nil
    @stdout_worker = nil

  end

  def start_as
    @as_worker = Thread.new { @as.run_till_terminated }
  end

  def stop_as
    @as.stop
    @as_worker.join
  end

  def start_docker

    @stdin, @stdout, @waiter = Open3.popen2e("docker-compose --file #{COMPOSE_FILE} up")
    @stdout_worker = Thread.new do
      @stdout.each_line do |line|
        @logger.info{line.strip}
      end
    end

    # takes a while for the containers to start and postgres to init
    # todo: poll for startup
    sleep 10

  end

  def stop_docker
    Process.kill("INT", @waiter.pid)
    Process.wait(@waiter.pid)
    @stdout_worker.join
    @stdout.close
    @stdin.close
  end

  def start
    start_as()
    @js.start
    start_docker()
    add_routing_profiles()
  end

  def stop
    stop_docker()
    stop_as()
    @js.stop
  end

  def add_routing_profiles
    with_mutex do
      @stubs.each do |region,stub|
        stub.create_routing_profile(
          NS::CreateRoutingProfileRequest.new(
            routing_profile: NS::RoutingProfile.new(
              id: "default",
              as_id: "#{LOCALHOST}:#{AS_PORT}"
            )
          )
        )
      end
    end
  end

  def get_version(scenario)
    stub(scenario).get_version(Google::Protobuf::Empty.new)
  end

  def add_scenario(scenario, **opts)

    remove_scenario(scenario)

    with_mutex do

      service_profile = NS::ServiceProfile.new(
        id: scenario.device.dev_eui,
        add_gw_metadata: true,
        dr_min: 0,
        dr_max: 5
      )

      device_profile = NS::DeviceProfile.new(
        id: scenario.device.dev_eui,
        mac_version: "1.0.3",
        reg_params_revision: "B",
        supports_32bit_f_cnt: true,
        max_eirp: 16,
        max_duty_cycle: 100,
        supports_join: true
      )

      gateway = NS::Gateway.new(
        id: scenario.gw.eui,
        location: ChirpStackAPI::Common::Location.new,
        routing_profile_id: "default"
      )

      device = NS::Device.new(
        dev_eui: scenario.device.dev_eui,
        service_profile_id: service_profile.id,
        device_profile_id: device_profile.id,
        routing_profile_id: "default"
      )

      # add them

      stub(scenario).create_device_profile(NS::CreateDeviceProfileRequest.new(device_profile: device_profile))
      stub(scenario).create_service_profile(NS::CreateServiceProfileRequest.new(service_profile: service_profile))
      stub(scenario).create_gateway(NS::CreateGatewayRequest.new(gateway: gateway))
      stub(scenario).create_device(NS::CreateDeviceRequest.new(device: device))

      @js.add_scenario(scenario)

      sleep 1

      self

    end

  end

  def remove_scenario(scenario)
    with_mutex do

      begin
        stub(scenario).delete_device(NS::DeleteDeviceRequest.new(dev_eui: scenario.device.dev_eui))
      rescue
      end

      begin
        stub(scenario).delete_device_profile(NS::DeleteDeviceProfileRequest.new(id: scenario.device.dev_eui))
      rescue
      end

      begin
        stub(scenario).delete_service_profile(NS::DeleteServiceProfileRequest.new(id: scenario.device.dev_eui))
      rescue
      end

      begin
        stub(scenario).delete_gateway(NS::DeleteGatewayRequest.new(id: scenario.gw.eui))
      rescue
      end

      @js.remove_scenario(scenario)

      self

    end
  end

  def stub(scenario)
    @stubs[scenario.region]
  end

  def with_mutex
    @mutex.synchronize do
      yield
    end
  end

  REGION_TO_CS = {
    EU_863_870: "EU868",
    US_902_928: "US915",
    AU_915_928: "AU915",
  }

  def region_to_cs(region)
    REGION_TO_CS[region]
  end

  private :with_mutex,
    :add_routing_profiles,
    :start_docker,
    :stop_docker,
    :start_as,
    :stop_as,
    :stub,
    :region_to_cs

end
