require 'chirpstack_api'
require 'securerandom'
require 'open3'

require_relative 'join_server'
require_relative 'app_server'

class ChirpStack

  NS = ChirpStackAPI::NS

  # magical barely documented address that maps to localhost from inside docker compose
  LOCALHOST = "172.17.0.1"

  COMPOSE_FILE = File.expand_path(File.join(File.dirname(__FILE__), "compose.yml"))

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

    #@config = YAML.load(COMPOSE_FILE)

    @stub = NS::NetworkServerService::Stub.new('localhost:8000', :this_channel_is_insecure)
    @js = JoinServer.new(logger: @logger)

    @as = GRPC::RpcServer.new
    @as.add_http2_port('0.0.0.0:9001', :this_port_is_insecure)
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
    add_routing_profile()
  end

  def stop
    stop_docker()
    stop_as()
    @js.stop
  end

  def add_routing_profile
    with_mutex do
      @stub.create_routing_profile(
        NS::CreateRoutingProfileRequest.new(
          routing_profile: NS::RoutingProfile.new(
              id: "default",
              as_id: "#{LOCALHOST}:9001"
            )
        )
      )
    end
  end

  def get_version
    @stub.get_version(Google::Protobuf::Empty.new)
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
        mac_version: "1.0.2",
        reg_params_revision: "B",
        supports_32bit_f_cnt: true,
        max_eirp: 14,
        max_duty_cycle: 100,
        supports_join: true,
        rf_region: "EU868"
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

      @stub.create_device_profile(NS::CreateDeviceProfileRequest.new(device_profile: device_profile))
      @stub.create_service_profile(NS::CreateServiceProfileRequest.new(service_profile: service_profile))
      @stub.create_gateway(NS::CreateGatewayRequest.new(gateway: gateway))
      @stub.create_device(NS::CreateDeviceRequest.new(device: device))

      @js.add_scenario(scenario)

      self

    end

  end

  def remove_scenario(scenario)
    with_mutex do

      begin
        @stub.delete_device(NS::DeleteDeviceRequest.new(dev_eui: scenario.device.dev_eui))
      rescue
      end

      begin
        @stub.delete_device_profile(NS::DeleteDeviceProfileRequest.new(id: scenario.device.dev_eui))
      rescue
      end

      begin
        @stub.delete_service_profile(NS::DeleteServiceProfileRequest.new(id: scenario.device.dev_eui))
      rescue
      end

      begin
        @stub.delete_gateway(NS::DeleteGatewayRequest.new(id: scenario.gw.eui))
      rescue
      end

      @js.remove_scenario(scenario)

      self

    end
  end

  def with_mutex
    @mutex.synchronize do
      yield
    end
  end

  private :with_mutex,
    :add_routing_profile,
    :start_docker,
    :stop_docker,
    :start_as,
    :stop_as

end
