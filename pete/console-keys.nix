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
    "QJhubjStzXZiCJ0+gxOuUh7qXSOfoOeMQ+VhG8w9rMmPkfmgGlXhIv9FCHH9ITgthznLbXiQdldL5Hl3gPJm3w==,QFlJ1JV3W53qRY3Lv/HrleJcNeCkkAD4/eNpBvvHejMt0vsEWdnF/ThaI3e48EtB4uZuVmaAIevyfdrMsvwx9g==,es256,+presence"
    # Backup YubiKey
    "iVeYN+JIHdFG4BmjPbuKMGcAHQysan+cadDGGNdWQClRLL6mFPvbrJYjDGbZhAes7q9bmVDAU0ET0UQG5UaINg==,Gb0pZvKg9+EokUqiu4243o7IXstpibYbue3xvqV0MjMBPjZRlRr4u3i+gkzrAq2Knu2WD28dLb3iinImE8NnrQ==,es256,+presence"
  ];
}
