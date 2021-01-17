require 'openssl'
require_relative 'codec'

module Flora

  class SecurityModule

    #include LoggerMethods

    OPTS = {}

    def initialize(opts=OPTS)
      @logger = opts[:logger]||NULL_LOGGER
    end

    def mic(key, *data)

      kek = OpenSSL::Cipher.new("AES-128-ECB").encrypt
      kek.padding = 0
      kek.key = key

      k = kek.update("\x00" * 16).bytes

      k1k2 = Array.new(2).map do
        k = k.pack("C*").unpack('B*').first
        msb = k.slice!(0)
        k = [k, '0'].pack('B*').bytes
        k[15] ^= 0x87 if msb == '1'
        k.dup
      end

      cipher = OpenSSL::Cipher.new("AES-128-CBC").encrypt
      cipher.key = key
      cipher.iv = ("\x00" * 16)

      buffer = data.join

      while buffer.size > 16 do

        cipher.update(buffer.slice!(0...16))

      end

      block = buffer.bytes
      buffer.clear

      k = k1k2[block.size == 16 ? 0 : 1].dup

      i = block.size.times { |ii| k[ii] ^= block[ii] }

      if i < 16

        k[i] ^= 0x80 if i < 16

      end

      mac = cipher.update(k.pack('C*')) + cipher.final

      mac.unpack("L<").first

    end

    def ctr(key, iv, data)

      return data if data.empty?

      cipher = OpenSSL::Cipher.new("AES-128-CTR").encrypt
      cipher.padding =  0
      cipher.key = key
      cipher.iv = iv

      cipher.update(data) + cipher.final

    end

    def ecb_encrypt(key, data)

      cipher = OpenSSL::Cipher.new("AES-128-ECB").encrypt
      cipher.padding = 0
      cipher.key = key

      cipher.update(data)

    end

    def ecb_decrypt(key, data)

      raise ArgumentError unless (data.size % 16) == 0

      cipher = OpenSSL::Cipher.new("AES-128-ECB").decrypt
      cipher.padding = 0
      cipher.key = key

      cipher.update(data)

    end

    # LoRaWAN 1.0 derivation
    def derive_keys(nwk_key, join_nonce, net_id, dev_nonce)

      retval = {}

      nwk = OpenSSL::Cipher.new("AES-128-ECB").encrypt
      nwk.key = nwk_key

      iv = OutputCodec.new.put_u24(join_nonce).put_u24(net_id).put_u16(dev_nonce).put_bytes("\x00\x00\x00\x00\x00\x00\x00").output

      retval[:apps] = nwk.update("\x02".concat(iv))
      retval[:fnwksint] = nwk.update("\x01".concat(iv))

      retval[:snwksint] = retval[:fnwksint]
      retval[:nwksenc] = retval[:fnwksint]
      retval[:jsenc] = retval[:fnwksint]
      retval[:jsint] = retval[:fnwksint]

      retval

    end

    # LoRaWAN 1.1 derivation
    def derive_keys2(nwk_key, app_key, join_nonce, join_eui, dev_nonce, dev_eui)

      retval = {}

      iv = OutputCodec.new.put_u24(join_nonce).put_eui(join_eui).put_u16(dev_nonce).put_u16(0).output
      join_iv = OutputCodec.new.put_eui(dev_eui).put_bytes("\x00" * 7).output

      nwk = OpenSSL::Cipher.new("AES-128-ECB").encrypt
      nwk.key = nwk_key

      retval[:jsenc] =    nwk.update("\x05".concat(join_iv))
      retval[:jsint] =    nwk.update("\x06".concat(join_iv))
      retval[:fnwksint] = nwk.update("\x01".concat(iv))
      retval[:snwksint] = nwk.update("\x03".concat(iv))
      retval[:nwksenc] =  nwk.update("\x04".concat(iv))

      if key(:app)

        app = OpenSSL::Cipher.new("AES-128-ECB").encrypt
        app.key = app_key

        retval[:apps] = app.update("\x02".concat(iv))

      end

      retval

    end

    def init_a(dev_addr, upstream, counter)

      out = OutputCodec.new(logger: @logger)

      out.put_u8(1)
      out.put_u32(0)
      out.put_u8(upstream ? 0 : 1)
      out.put_u32(dev_addr)
      out.put_u32(counter)
      out.put_u16(0)

      out.output

    end

    def init_b(confirm_counter, rate, ch_index, upstream, dev_addr, counter, len)

      out = OutputCodec.new(logger: @logger)

      out.put_u8(0x49)
      out.put_u16(confirm_counter)
      out.put_u8(rate)
      out.put_u8(ch_index)
      out.put_u8(upstream ? 0 : 1)
      out.put_u32(dev_addr)
      out.put_u32(counter)
      out.put_u8(0)
      out.put_u8(len)

      out.output

    end

  end

end
