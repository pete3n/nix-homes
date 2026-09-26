# Console-login (pam_u2f) credentials for people on this network's
# Workstations, for the domain's pamOrigin (pam://p22.lan).
#
# Interim: the Roster will generate this list (ADR-0014). Until then it is
# kept by hand. List every YubiKey a person owns, Backup Key included, or
# the missing one can't log in. Enroll each key with
#
#   pamu2fcfg -n -o pam://p22.lan -i pam://p22.lan
#
# and paste the output line. The PIN is asked for by each service's PAM
# policy (u2fPin), so the credential itself doesn't need +pin.
{
  pete = [
    # Primary YubiKey

    # Backup YubiKey

  ];
}
