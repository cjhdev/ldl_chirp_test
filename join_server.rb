require 'sinatra/base'
require 'sinatra/custom_logger'
require 'flora'

class JoinServer

  DEV = Struct.new(:dev_eui, :nwk_key, :app_key, :version, :dev_nonce, :join_nonce, keyword_init: true)



  def initialize(**opts)

    @logger = opts[:logger]||NULL_LOGGER

    @port = opts[:port]||8003
    @host = opts[:host]||"0.0.0.0"

    @devices = {}

    @app = Sinatra.new do

      helpers Sinatra::CustomLogger

      post '/' do

        content_type 'application/json'
        request.body.rewind
        settings.user.process_object(JSON.parse(request.body.read)).to_json

      end

    end

    @app.set :port, @port
    @app.set :bind, @host
    @app.set :user, self
    @app.set :traps, false
    @app.set :logger, @logger

  end

  def add_device(**opts)

    dev = DEV.new(
      dev_eui: opts[:dev_eui],
      nwk_key: opts[:nwk_key],
      app_key: opts[:app_key],
      version: 0,
      join_nonce: 0
    )

    dev.dev_nonce = opts[:dev_nonce]||0

    @devices[opts[:dev_eui]] = dev

  end

  def remove_device(dev_eui)
    @devices.delete(dev_eui)
  end

  def add_scenario(scenario)
    add_device(
      dev_eui: scenario.device.dev_eui,
      nwk_key: scenario.device.nwk_key,
      app_key: scenario.device.app_key
    )
  end

  def remove_scenario(scenario)
    remove_device(scenario.device.dev_eui)
  end

  def start
    @worker = Thread.new do
      @app.start!
    end
  end

  def stop
    @app.quit!
    @worker.join
  end

  def process_object(input)

    case input["MessageType"]
    when "JoinReq"
      process_join_request(parse_input(input))
    else
      {
        ProtocolVersion: msg["ProtocolVersion"],
        SenderID: input["receiverID"],
        ReceiverID: input["SenderID"],
        TransactionID: input["TransactionID"],
        Result: {ResultCode: "Failure"}
      }
    end

  end

  def process_join_request(input)

    frame = Flora::FrameDecoder.new(logger: @logger).decode(input["PHYPayload"])

    net_id = input["SenderID"]

    device = @devices[frame.dev_eui]

    if device.nil? or (device.dev_nonce > frame.dev_nonce)
      return {
        ProtocolVersion: input["ProtocolVersion"],
        SenderID: input["receiverID"],
        ReceiverID: net_id.to_s(16),
        TransactionID: input["TransactionID"],
        Result: {ResultCode: "Failure"}
      }
    end

    sm = Flora::SecurityModule.new(
      {
        nwk: [device.nwk_key].pack("m0"),
        app: [device.app_key].pack("m0")
      },
      logger: @logger
    )

    sm.derive_keys(device.join_nonce, net_id, frame.dev_nonce)

    device.dev_nonce = frame.dev_nonce

    response = Flora::OutputCodec.new.
      put_u8(1 << 5).
      put_u24(device.join_nonce).
      put_u24(net_id).
      put_u32(input["DevAddr"]).
      put_u8(input["DLSettings"]).
      put_u8(input["RxDelay"]).
      put_bytes(input["CFList"]).
      #put_u32(mic).
      output

    obj = {
      ProtocolVersion: input["ProtocolVersion"],
      SenderID: input["receiverID"],
      ReceiverID: net_id.to_s(16),
      TransactionID: input["TransactionID"],
      MessageType: "JoinAns",
      Result: {ResultCode: "Success"},
      Lifetime: 0
      #SessionKeyID:
      #SenderToken:
      #ReceiverToken:

    }

    if input["MacVersion"] == "1.1"

      hdr = FLora::OutputCodec.new.put_u8(0xff).put_eui(frame.join_eui).put_u16(frame.dev_nonce).output

      Flora::OutputCodec.new(response).put_u32(sm.mic(:jsint, hdr, response))

      obj[:SNwkSIntKey] = to_key(sm.get(:snwksint))
      obj[:FNwkSIntKey] = to_key(sm.get(:fnwksint))
      obj[:NwkSEncKey] = to_key(sm.get(:nwksenc))
      obj[:NwkSKey] = to_key(sm.get(:nwks))
      obj[:AppSKey] = to_key(sm.get(:apps))

    else

      Flora::OutputCodec.new(response).put_u32(sm.mic(:nwk, response))

      obj[:NwkSKey] = to_key(sm.get(:fnwksint))
      obj[:AppSKey] = to_key(sm.get(:apps))

    end

    response.concat sm.ecb_decrypt(:nwk, response.slice!(1..-1))

    obj[:PHYPayload] = to_hex(response)

    obj

  end

  def parse_input(input)

    output = input.dup

    output["PHYPayload"] = [input["PHYPayload"]].pack("H*") if input["PHYPayload"]
    output["DevAddr"] = input["DevAddr"].to_i(16) if input["DevAddr"]
    output["DevEUI"] = [input["DevEUI"]].pack("H*") if input["DevEUI"]
    output["DLSettings"] = input["DLSettings"].to_i(16) if input["DLSettings"]
    output["RxDelay"] = input["RxDelay"].to_i if input["RxDelay"]
    output["CFList"] = [input["CFList"]].pack("H*") if input["CFList"]
    output["SenderID"] = input["SenderID"].to_i(16) if input["SenderID"]

    output

  end

  def to_key(key)
    {
      AESKey: to_hex(key)
    }
  end

  def to_hex(input)
   input.bytes.map{|b|"%02X"%b}.join
  end

  private :parse_input, :process_join_request, :to_hex, :to_key

end

=begin
{
"ProtocolVersion":"1.0",
"SenderID":"000000",
"ReceiverID":"f461e03ca2c34a16",
"TransactionID":721336316,
"MessageType":"JoinReq",
"VSExtension":{},
"MACVersion":"1.0.2",
"PHYPayload":"00164ac3a23ce061f458dcba1e74f0e8fc00002439b898",
"DevEUI":"fce8f0741ebadc58",
"DevAddr":"00c14751",
"DLSettings":"00",
"RxDelay":1,
"CFList":"184f84e85684b85e84886684586e8400"
}
172.22.0.2 - - [18/Dec/2020:12:00:05 GMT] "POST / HTTP/1.1" 200 0
=end
