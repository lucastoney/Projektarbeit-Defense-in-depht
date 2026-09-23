lab_password = ENV.fetch("LAB_PASSWORD", "")

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_check_update = false

  config.vm.define "server" do |server|
    server.vm.hostname = "security-server"
    server.vm.network "private_network", ip: "192.168.56.10"
    server.vm.provider "virtualbox" do |vb|
      vb.name = "defense-in-depth-server"
      vb.memory = 1536
      vb.cpus = 2
    end
    server.vm.provision "shell",
      path: "scripts/provision-server.sh",
      env: { "LAB_PASSWORD" => lab_password }
  end

  config.vm.define "tester" do |tester|
    tester.vm.hostname = "security-tester"
    tester.vm.network "private_network", ip: "192.168.56.20"
    tester.vm.provider "virtualbox" do |vb|
      vb.name = "defense-in-depth-tester"
      vb.memory = 768
      vb.cpus = 1
    end
    tester.vm.provision "shell",
      path: "scripts/provision-tester.sh",
      env: { "LAB_PASSWORD" => lab_password }
  end
end
