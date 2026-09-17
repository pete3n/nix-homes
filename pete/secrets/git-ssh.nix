{ nixSpaceAttrs, ... }:
{
  age.secrets.githubSshKey = {
    file = ./pete3n.age;
    path = "/home/${nixSpaceAttrs.user}/.ssh/pete3n";
    owner = nixSpaceAttrs.user;
    mode = "0600";
  };
}
