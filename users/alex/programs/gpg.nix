{ ... }:
{
  enable = true;
  settings = {
    # prefer modern algorithms
    personal-cipher-preferences = "AES256 AES192 AES";
    personal-digest-preferences = "SHA512 SHA384 SHA256";
    personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";

    # modern defaults
    default-new-key-algo = "ed25519/cert,sign+cv25519/encr";
    default-preference-list = "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP";

    # long fingerprints
    keyid-format = "long";
    with-fingerprint = true;

    # stronger cert digests
    cert-digest-algo = "SHA512";

    # trust model modern default
    trust-model = "tofu+pgp";
  };
}
