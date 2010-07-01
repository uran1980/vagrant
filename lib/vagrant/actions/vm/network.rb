module Vagrant
  module Actions
    module VM
      class Network < Base
        def before_destroy
          # We need to check if the host only network specified by any
          # of the adapters would not have any more clients if it was
          # destroyed. And if so, then destroy the host only network
          # itself.
          interfaces = runner.vm.network_adapters.collect do |adapter|
            adapter.host_interface_object
          end

          interfaces.compact.uniq.each do |interface|
            # Destroy the network interface if there is only one
            # attached VM (which must be this VM)
            if interface.attached_vms.length == 1
              logger.info "Destroying unused network interface..."
              interface.destroy
            end
          end
        end

        def before_boot
          assign_network if enable_network?
        end

        def after_boot
          if enable_network?
            logger.info "Enabling host only network..."

            runner.system.prepare_host_only_network

            runner.env.config.vm.network_options.compact.each do |network_options|
              runner.system.enable_host_only_network(network_options)
            end
          end
        end

        def enable_network?
          !runner.env.config.vm.network_options.compact.empty?
        end

        # Enables and assigns the host only network to the proper
        # adapter on the VM, and saves the adapter.
        def assign_network
          logger.info "Preparing host only network..."

          runner.env.config.vm.network_options.compact.each do |network_options|
            adapter = runner.vm.network_adapters[network_options[:adapter]]
            adapter.enabled = true
            adapter.attachment_type = :host_only
            adapter.host_interface = network_name(network_options)
            adapter.save
          end
        end

        # Returns the name of the proper host only network, or creates
        # it if it does not exist. Vagrant determines if the host only
        # network exists by comparing the netmask and the IP.
        def network_name(net_options)
          # First try to find a matching network
          interfaces = VirtualBox::Global.global.host.network_interfaces
          interfaces.each do |ni|
            # Ignore non-host only interfaces which may also match,
            # since they're not valid options.
            next if ni.interface_type != :host_only

            if net_options[:name]
              return ni.name if net_options[:name] == ni.name
            else
              return ni.name if matching_network?(ni, net_options)
            end
          end

          raise ActionException.new(:network_not_found, :name => net_options[:name]) if net_options[:name]

          # One doesn't exist, create it.
          logger.info "Creating new host only network for environment..."

          ni = interfaces.create
          ni.enable_static(network_ip(net_options[:ip], net_options[:netmask]),
                           net_options[:netmask])
          ni.name
        end

        # Tests if a network matches the given options by applying the
        # netmask to the IP of the network and also to the IP of the
        # virtual machine and see if they match.
        def matching_network?(interface, net_options)
          interface.network_mask == net_options[:netmask] &&
            apply_netmask(interface.ip_address, interface.network_mask) ==
            apply_netmask(net_options[:ip], net_options[:netmask])
        end

        # Applies a netmask to an IP and returns the corresponding
        # parts.
        def apply_netmask(ip, netmask)
          ip = split_ip(ip)
          netmask = split_ip(netmask)

          ip.map do |part|
            part & netmask.shift
          end
        end

        # Splits an IP and converts each portion into an int.
        def split_ip(ip)
          ip.split(".").map do |i|
            i.to_i
          end
        end

        # Returns a "network IP" which is a "good choice" for the IP
        # for the actual network based on the netmask.
        def network_ip(ip, netmask)
          parts = apply_netmask(ip, netmask)
          parts[3] += 1;
          parts.join(".")
        end
      end
    end
  end
end