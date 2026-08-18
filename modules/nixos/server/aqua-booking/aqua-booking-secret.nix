_: {
  flake.modules.nixos.aqua-booking-secret =
    { config, ... }:
    {
      age.secrets.aqua-credentials.rekeyFile = ./secrets/aqua-credentials.age;
      blizzard.aqua-booking.secretsFile = config.age.secrets.aqua-credentials.path;
    };
}
