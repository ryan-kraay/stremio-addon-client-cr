require "bitfields"
require "random/secure"
require "openssl/digest"
require "openssl/cipher"
require "base64"
require "lz4/writer"
require "./keyring"

module Stremio::Addon::DevKit::UserData


  class V1(T)

    # Our enrypted userdata contains a custom header.  We can support different versions of these header.
    # This class defines Version 1.
    # WARNING: Headers are stored and transmitted as big endian (aka: network byte order)
    class Header < BitFields
      # NOTE: BitFields' first entry is the LEAST Significant Bit

      #
      # HIGH BYTE - LSB first
      #

      # Reserved for future expansion
      bf reserve : UInt8, 1
      # Refers to the position in `Stremio::Addon::DevKit::UserData::KeyRing`
      bf keyring : UInt8, 3
      # Toggles if compression was used or not
      bf compress : UInt8, 1
      # Space to store which Header version was used
      # WARNING: Required for ALL headers and MUST be the Most Significant Bit
      bf version : UInt8, 3

      #
      # BYTE BOUNDARY
      #
      # LOW BYTE - LSB first
      #

      # A fragement of the random Initial Vector used for encryption
      bf iv_random : UInt8, 8

      #
      # END BIT-VECTOR
      #

      # The version we register as (must fit within `@version`)
      VERSION = 1_u8

      # Returns a `Header` constructed with `bytes`
      # Paramaters:
      #  * `bytes`: The header in network byte order, meaning bytes[0] contains the "high" bits
      #
      # WARNING: the use of `Header.new()` should be avoided (and for some reason we cannot create our own initialize()
      def self.create(bytes : Bytes)
        Header.new(bytes)
      end

      #
      # Returns an empty `Header` header with the version set
      #
      # Parameters:
      #  * `random_generator` uses a pseudo or real random number generator, `::Random#new` can be used for unit tests
      # WARNING: the use of `Header.new()` should be avoided (and for some reason we cannot create our own initialize()
      def self.create(random_generator = Random::Secure)
        rtn = Header.new Bytes[0, 0]
        rtn.version = Header::VERSION
        rtn.iv_random = {% begin %}
          b = Bytes[0]
          random_generator.random_bytes(b)
          b[0]
        {% end %}
        rtn
      end

      # Returns a cryptocraphically random initial vector
      # Paramaters:
      #  * `iv_static`: An optional fragement of the initial vector.  The `iv_random` + `iv_static` create enough entropy that we can build a suitable iv
      def iv(iv_static)
        hash = OpenSSL::Digest.new("SHA256")
        hash.update(Bytes[iv_random])
        hash.update(iv_static)
        hash.final
        # hash.hexfinal
      end

      # :ditto:
      def iv(iv_static : ::Nil)
        hash = OpenSSL::Digest.new("SHA256")
        hash.update(Bytes[iv_random])
        hash.final
        # hash.hexfinal
      end
    end  # END of `Header`

    # Constructs UserData Version 1 Interface
    #
    # Parameters:
    #  - `@ring` can either be a `KeyRing` or `KeyRing::Opt::Disable`
    #  - `@iv_static` a static portion of the initial vector used to encrypt the user data
    #
    # WARNING: Using `KeyRing::Opt::Disable` means that encryption will *not* be used
    def initialize(@ring : KeyRing | KeyRing::Opt, @iv_static : T)
    end

    def encode(data, compress : Bool = true, random_generator = Random::Secure) : String
      header = Header.create random_generator
      header.compress = compress == true ? 1_u8 : 0_u8
      if @ring.is_a?(KeyRing)
        # we want to find all the positions in our keyring, where the value is not nil
        used_positions = @ring.as(KeyRing).map_with_index do |secret, pos|
            # Combine our values with their index/position
            {pos, secret}
          end.select do |pair|
            # Filter out values that are nil
            !pair[1].nil?
          end.map do |pair|
            # return the index
            pair[0]
          end
        # Raise an error if used_positions is empty. aka our KeyRing is empty
        raise IndexError.new("Empty KeyRing, use KeyRing::Opt::Disable") if used_positions.empty?

        # Randomly choose from one of the available indexes
        index = random_generator.rand(0..used_positions.size - 1)
        header.keyring = used_positions[index].to_u8  # Our chosen keyring
      end

      encode(data.to_slice, header)
    end

    protected def encode(data : Slice, header : Header) : String
      # https://stackoverflow.com/questions/43565569/are-there-alternatives-to-begin-end-with-stricter-scope
      # To Read: https://crystal-lang.org/reference/1.8/syntax_and_semantics/macros/index.html
      base64 = {% begin %}
        aesio = {% begin %}
          # create/write the self.header
          lz4io = {% begin %}
              buf = IO::Memory.new
              if header.compress
                # enable compression
                Compress::LZ4::Writer.open(buf) do |br|
                  br.write data
                end
              else
                # we just write the data in plain text
                buf.write data
              end
              buf.rewind
              buf
          {% end %}

          buf = IO::Memory.new
          buf.write(header.to_slice) # Write our header first in plain-text
          if @ring.is_a?(KeyRing)
            cipher = OpenSSL::Cipher.new("aes-256-cbc")
            cipher.encrypt
            cipher.key = @ring.as(KeyRing)[ header.keyring ].as(String).to_slice
            cipher.iv = header.iv(@iv_static)

            buf.write(cipher.update lz4io)           # Write our payload
            buf.write(cipher.final)                  # Finalize the payload
            puts "RKR: Written"
          elsif @ring.is_a?(KeyRing::Opt) && @ring.as(KeyRing::Opt) == KeyRing::Opt::Disable
            buf.write(lz4io.to_slice)           # Write our payload  # WARNING:  Our payload is actually duplicated
            puts "RKR: Plain-text"
          else
            raise Exception.new("Unreachable")
          end
          buf.rewind

          puts buf.to_slice
          buf.rewind
          buf
        {% end %}
        Base64.urlsafe_encode data = aesio, padding = false
      {% end %}
      base64
    end
  end
end
