# License:: Apache License, Version 2.0

require 'chef/knife'
require 'chef/knife/base_vsphere_command'
require 'rbvmomi'
require 'netaddr'

class Chef::Knife::VsphereVmCdrom < Chef::Knife::BaseVsphereCommand
  banner 'knife vsphere vm cdrom VMNAME (options)'

  EMPTY_DEVICE_NAME = ''.freeze

  common_options

  option :datastore,
         long: '--datastore STORE',
         description: 'The datastore for an iso source'

  option :iso,
         long: '--iso ISO',
         description: 'The name and path of the ISO to attach'

  option :attach,
         short: '-a',
         long: '--attach',
         description: 'Attach the virtual cdrom to the VM',
         boolean: true

  option :disconnect,
         long: '--disconnect',
         description: 'Disconnect the virtual cdrom from the VM',
         boolean: true

  option :on_boot,
         long: '--on_boot ONBOOT',
         description: 'False for Detached on boot or True for Attached on boot'

  option :client_device,
         long: '--client_device',
         description: 'Set the backing store to client-device'

  option :recursive,
         short: '-r',
         long: '--recursive',
         description: 'Search all folders'

  def run
    $stdout.sync = true

    vmname = @name_args[0]
    if vmname.nil?
      show_usage
      fatal_exit('You must specify a virtual machine name')
    end

    unless get_config(:attach) ^ get_config(:disconnect)
      fatal_exit('You must specify one of --attach or --disconnect')
    end

    fatal_exit 'You must specify the name and path of an ISO with --iso' if get_config(:attach) && !get_config(:iso)
    fatal_exit 'You must specify the datastore containing the ISO with --datastore' if get_config(:attach) && !get_config(:datastore)

    vim_connection

    if get_config(:recursive)
      vms = get_vms(vmname)
      if vms.length > 1
        fatal_exit "More than one VM with name #{vmname} found:\n" + vms.map { |vm| get_path_to_object(vm) }.join("\n")
      end
      fatal_exit "VM #{vmname} not found" if vms.empty?
      vm = vms[0]
    else
      base_folder = find_folder(get_config(:folder))

      vm = find_in_folder(base_folder, RbVmomi::VIM::VirtualMachine, vmname) || fatal_exit("VM #{vmname} not found")
    end

    cdrom_obj = vm.config.hardware.device.find { |hw| hw.class == RbVmomi::VIM::VirtualCdrom }
    fatal_exit 'Could not find a cd drive' unless cdrom_obj

    backing = if get_config(:attach)
                RbVmomi::VIM::VirtualCdromIsoBackingInfo(
                  fileName: iso_path
                )
              else
                RbVmomi::VIM::VirtualCdromRemoteAtapiBackingInfo(deviceName: EMPTY_DEVICE_NAME)
              end

    vm.ReconfigVM_Task(
      spec: spec(cdrom_obj, backing)
    ).wait_for_completion
  end

  private

  def spec(cd_device, backing)
    RbVmomi::VIM::VirtualMachineConfigSpec(
      deviceChange: [{
        operation: :edit,
        device: RbVmomi::VIM::VirtualCdrom(
          backing: backing,
          key: cd_device.key,
          controllerKey: cd_device.controllerKey,
          connectable: RbVmomi::VIM::VirtualDeviceConnectInfo(
            startConnected: get_config(:on_boot) || false,
            connected: get_config(:attach) || false,
            allowGuestControl: true
          )
        )
      }]
    )
  end

  def iso_path
    "[#{get_config(:datastore)}] #{get_config(:iso)}"
  end
end
