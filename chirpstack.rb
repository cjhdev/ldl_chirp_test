require 'chirpstack_api'
require 'securerandom'
require 'open3'

require_relative 'join_server'
require_relative 'app_server'

require_relative 'security_module'
require_relative 'codec'
require_relative 'frame_decoder'
require_relative 'small_event'

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

  def lookup_scenario(dev_eui)
    @scenarios.detect{|s|s.device.dev_eui == dev_eui}
  end

  def initialize(**opts)

    @logger = opts[:logger]||NULL_LOGGER
    @mutex = Mutex.new

    @broker = SmallEvent::Broker.new

    @stubs = {}

    @scenarios = []

    @confirmed_downlinks = {}

    @sm = Flora::SecurityModule.new(logger: @logger)

    @stubs[:EU_863_870] = NS::NetworkServerService::Stub.new('localhost:9000', :this_channel_is_insecure)
    @stubs[:US_902_928] = NS::NetworkServerService::Stub.new('localhost:9001', :this_channel_is_insecure)
    @stubs[:AU_915_928] = NS::NetworkServerService::Stub.new('localhost:9002', :this_channel_is_insecure)

    @js = JoinServer.new(logger: @logger, port: JS_PORT)

    @as = GRPC::RpcServer.new
    @as.add_http2_port("0.0.0.0:#{AS_PORT}", :this_port_is_insecure)
    @as.handle(
      AppServer.new do |m, arg|

        begin

          @logger.info arg

          case m
          when :handle_downlink_ack

            with_mutex do

              scenario = lookup_scenario(arg.dev_eui)

              dl = @confirmed_downlinks[scenario]

              break unless dl

              item = dl.detect{|m|m[:f_cnt] == arg.f_cnt}

              break unless item

              dl.delete(item)

              unless arg.acknowledged

                stub(scenario).create_device_queue_item(
                  NS::CreateDeviceQueueItemRequest.new(
                    item: make_downlink(scenario, item[:port], item[:data], item[:confirmed])
                  )
                )

              end

            end

          when :handle_uplink_data

            scenario = @scenarios.detect{|s|s.device.dev_eui == arg.dev_eui}

            break unless scenario

            data = decrypt_upstream(scenario, arg.data, arg.f_cnt) if arg.respond_to? :data
            port = arg.f_port if arg.respond_to? :f_port

            @broker.publish({data: data, port: port}, arg.dev_eui)

          else
            @logger.error{"no handler for '#{m}'"}
          end

        rescue => e
          @logger.error{e.to_s}
        end

      end
    )

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
        mac_version: "1.0.4",
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

      @scenarios << scenario

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

      @scenarios.delete(scenario)

      self

    end
  end

  def init_up_a(dev_addr, counter, i=1)

    Flora::OutputCodec.new.
      put_u8(1).
      put_u32(0).
      put_u8(0).
      put_u32(dev_addr).
      put_u32(counter).
      put_u8(0).
      put_u8(i).
      output

  end

   def init_down_a(dev_addr, counter, i=1)

    Flora::OutputCodec.new.
      put_u8(1).
      put_u32(0).
      put_u8(1).
      put_u32(dev_addr).
      put_u32(counter).
      put_u8(0).
      put_u8(i).
      output

  end

  def decrypt_upstream(scenario, data, counter)
    @sm.ctr(scenario.device.keys[:apps], init_up_a(scenario.device.dev_addr, counter), data)
  end

  def encrypt_downstream(scenario, data, counter)
    @sm.ctr(scenario.device.keys[:apps], init_down_a(scenario.device.dev_addr, counter), data)
  end

  def listen(scenario, &block)
    broker.subscribe scenario.dev_eui, &block
  end

  def unlisten(block)
    broker.unsubscribe(block)
  end

  def next_counter(scenario)
    stub(scenario).get_next_downlink_f_cnt_for_dev_eui(
      NS::GetNextDownlinkFCntForDevEUIRequest.new(
        dev_eui: scenario.device.dev_eui
      )
    ).f_cnt
  end

  def make_downlink(scenario, port, data, confirmed)

    f_cnt = next_counter(scenario)

    NS::DeviceQueueItem.new(
      dev_eui: scenario.device.dev_eui,
      frm_payload: encrypt_downstream(scenario, data, f_cnt),
      f_cnt: f_cnt,
      f_port: port,
      confirmed: confirmed,
      dev_addr: [scenario.device.dev_addr].pack("L>")
    )

  end

  def send_downlink(scenario, data="", **opts)

    with_mutex do

      confirmed = opts[:confirmed]||false
      port = opts[:port]||1

      item = make_downlink(scenario, port, data, confirmed)

      if confirmed
        @confirmed_downlinks[scenario] = [] unless @confirmed_downlinks[scenario]
        @confirmed_downlinks[scenario] << {port: port, data: data, confirmed: confirmed, f_cnt: item.f_cnt}
      end

      stub(scenario).create_device_queue_item(
        NS::CreateDeviceQueueItemRequest.new(
          item: item
        )
      )

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
