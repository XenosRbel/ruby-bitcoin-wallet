# frozen_string_literal: true

require 'bitcoin'

module Bitcoin
  module OpenSSL3Compat
    CURVE = 'secp256k1'

    class << self
      def group
        OpenSSL::PKey::EC::Group.new(CURVE)
      end

      # Полный ключ из hex-приватника: pub вычисляется, всё пакуется в SEC1 DER.
      def ec_key_from_private_hex(priv_hex)
        priv_hex = priv_hex.rjust(64, '0')
        pub_octets = group.generator
                          .mul(OpenSSL::BN.new(priv_hex, 16))
                          .to_octet_string(:uncompressed)
        asn1 = OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::Integer(1),
          OpenSSL::ASN1::OctetString([priv_hex].pack('H*')),
          OpenSSL::ASN1::ObjectId(CURVE, 0, :EXPLICIT),
          OpenSSL::ASN1::BitString(pub_octets, 1, :EXPLICIT)
        ])
        OpenSSL::PKey::EC.new(asn1.to_der)
      end

      def ec_key_from_public_hex(pub_hex)
        octets = [pub_hex].pack('H*')
        spki = OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::Sequence([
            OpenSSL::ASN1::ObjectId('id-ecPublicKey'),
            OpenSSL::ASN1::ObjectId(CURVE)
          ]),
          OpenSSL::ASN1::BitString(octets)
        ])
        OpenSSL::PKey.read(spki.to_der)
      end

      # Uncompressed hex-пабкей из hex-приватника (чистая EC-математика).
      def public_hex_from_private_hex(priv_hex)
        group.generator
             .mul(OpenSSL::BN.new(priv_hex.rjust(64, '0'), 16))
             .to_octet_string(:uncompressed).unpack1('H*')
      end
    end
  end

  module KeyOpenSSL3Compat
    def generate
      @key = OpenSSL::PKey::EC.generate(OpenSSL3Compat::CURVE)
      self
    end

    def priv
      return nil unless @key.private_key

      @key.private_key.to_s(16).rjust(64, '0')
    end

    def pub_compressed
      public_key = @key.public_key
      public_key.to_octet_string(:compressed).unpack1('H*').rjust(66, '0')
    end

    def pub_uncompressed
      public_key = @key.public_key
      public_key.to_octet_string(:uncompressed).unpack1('H*').rjust(130, '0')
    end

    protected

    def regenerate_pubkey
      return nil unless @key.private_key
      return @key.public_key if @key.public_key

      set_pub(OpenSSL3Compat.public_hex_from_private_hex(priv), @pubkey_compressed)
    end

    def set_priv(priv)
      value = priv.to_i(16)

      min = Bitcoin::Key::MIN_PRIV_KEY_MOD_ORDER
      max = Bitcoin::Key::MAX_PRIV_KEY_MOD_ORDER
      raise 'private key is not on curve' unless min <= value && value <= max

      @key = OpenSSL3Compat.ec_key_from_private_hex(priv)
    end

    def set_pub(pub, compressed = nil)
      @pubkey_compressed = compressed.nil? ? self.class.is_compressed_pubkey?(pub) : compressed
      @key = OpenSSL3Compat.ec_key_from_public_hex(pub)
    end
  end

  module BitcoinModuleOpenSSL3Compat
    def verify_signature(hash, signature, public_key)
      key = OpenSSL3Compat.ec_key_from_public_hex(public_key)
      signature = Bitcoin::OpenSSL_EC.repack_der_signature(signature)
      if signature
        key.dsa_verify_asn1(hash, signature)
      else
        false
      end
    rescue OpenSSL::PKey::ECError, OpenSSL::PKey::EC::Point::Error,
           OpenSSL::BNError, OpenSSL::PKey::PKeyError, OpenSSL::ASN1::ASN1Error
      false
    end

    def regenerate_public_key(private_key)
      OpenSSL3Compat.public_hex_from_private_hex(private_key)
    end
  end

  class Key
    prepend KeyOpenSSL3Compat
  end

  singleton_class.prepend(BitcoinModuleOpenSSL3Compat)
end
