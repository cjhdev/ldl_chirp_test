require 'sinatra/base'
require 'sinatra/custom_logger'
require_relative 'security_module'

class JoinServer

  SCENARIO = Struct.new(:state, :join_nonce, :version, keyword_init: true)

  def initialize(**opts)

    @logger = opts[:logger]||NULL_LOGGER

    @port = opts[:port]||8003
    @host = opts[:host]||"0.0.0.0"

    @scenarios = []

    @sm = Flora::SecurityModule.new(logger: @logger)

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

  def add_scenario(scenario)
    @scenarios.push(
      SCENARIO.new(
        state: scenario,
        join_nonce: 0,
        version: 0
      )
    )
  end

  def remove_scenario(scenario)
    @scenarios.delete_if{|s|s.state == scenario}
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

  def lookup_scenario(dev_eui)
    @scenarios.detect{|s|s.state.device.dev_eui == dev_eui}
  end

  def process_join_request(input)

    frame = Flora::FrameDecoder.new(logger: @logger).decode(input["PHYPayload"])

    net_id = input["SenderID"]

    s = lookup_scenario(frame.dev_eui)

    if s.nil?
      return {
        ProtocolVersion: input["ProtocolVersion"],
        SenderID: input["receiverID"],
        ReceiverID: net_id.to_s(16),
        TransactionID: input["TransactionID"],
        Result: {ResultCode: "Failure"}
      }
    end

    response = Flora::OutputCodec.new.
      put_u8(1 << 5).
      put_u24(s.join_nonce).
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

      @sm.derive_keys2(
        s.state.device.keys[:nwk],
        s.state.device.keys[:app],
        s.join_nonce,
        s.join_eui,
        frame.dev_nonce,
        frame.dev_eui

      ).tap do |keys|

        hdr = Flora::OutputCodec.new.put_u8(0xff).put_eui(frame.join_eui).put_u16(frame.dev_nonce).output

        Flora::OutputCodec.new(response).put_u32(@sm.mic(s.state.device.keys[:jsint], hdr, response))

        obj[:SNwkSIntKey] = to_key(keys[:snwksint])
        obj[:FNwkSIntKey] = to_key(keys[:fnwksint])
        obj[:NwkSEncKey] = to_key(keys[:nwksenc])
        obj[:NwkSKey] = to_key(keys[:nwks])
        obj[:AppSKey] = to_key(keys[:apps])

      end

    else

      @sm.derive_keys(
        s.state.device.keys[:nwk],
        s.join_nonce,
        net_id,
        frame.dev_nonce

      ).tap do |keys|

        Flora::OutputCodec.new(response).put_u32(@sm.mic(s.state.device.keys[:nwk], response))

        obj[:NwkSKey] = to_key(keys[:fnwksint])
        obj[:AppSKey] = to_key(keys[:apps])

      end

    end

    response.concat @sm.ecb_decrypt(s.state.device.keys[:nwk], response.slice!(1..-1))

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
