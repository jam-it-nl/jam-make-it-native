require "base64"
require "jwt"

apiKeyId = ARGV[0]
private_key = OpenSSL::PKey.read(ARGV[1])
issuerId = ARGV[2]

token = JWT.encode(
  {
    iss: issuerId,
    exp: Time.now.to_i + 20 * 60,
    aud: "appstoreconnect-v1",
  }, private_key, "ES256", header_fields = {
    kid: apiKeyId,
  }
)
puts token
