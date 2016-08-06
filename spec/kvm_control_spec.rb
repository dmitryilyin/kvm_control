require 'spec_helper'
require_relative '../kvm_control'

describe KvmControl do
  before(:each) do
    subject.options = {
        :virt => 'kvm',
        :pool => 'default',
    }
  end

  context 'create' do

    it 'can create an empty domain' do
      expected_command = %w(virt-install --name test --ram 1024 --vcpus 2,cores=2 --os-type linux --virt-type kvm --pxe
    --boot network,hd --noautoconsole --graphics vnc,listen=0.0.0.0 --autostart)
      expect(subject).to receive(:run).with(expected_command).and_return(['', true])
      subject.domain_create 'test', {}
    end

    it 'can create a domain with networks' do
      expected_command = %w(virt-install --name test --ram 1024 --vcpus 2,cores=2 --os-type linux --virt-type kvm --pxe
    --boot network,hd --noautoconsole --graphics vnc,listen=0.0.0.0 --autostart
    --network network=pxe,mac=52:54:00:6d:38:8f,model=virtio --network network=default,model=virtio)
      expect(subject).to receive(:run).with(expected_command).and_return(['', true])
      subject.domain_create 'test', {
          'networks' => [
              {
                  'network' => 'pxe',
                  'mac' => '52:54:00:6d:38:8f',
              },
              {
                  'network' => 'default',
              },
          ],
      }
    end

    it 'can create a domain with volumes' do
      expected_command = %w(virt-install --name test --ram 1024 --vcpus 2,cores=2 --os-type linux --virt-type kvm
      --pxe --boot network,hd --noautoconsole --graphics vnc,listen=0.0.0.0 --autostart
      --disk path=/test/1,serial=101,cache=none,bus=virtio --disk path=/test/2,serial=102,cache=none,bus=virtio)
      expect(subject).to receive(:run).with(expected_command).and_return(['', true])
      subject.domain_create 'test', {
          'volumes' => [
              {
                  'path' => '/test/1',
                  'name' => 'test1_os',
                  'size' => 1,
                  'serial' => 101,
              },
              {
                  'path' => '/test/2',
                  'name' => 'test1_app',
                  'size' => 1,
                  'serial' => 102,
              },
          ],
      }
    end

    it 'can create a complex domain' do
      expected_command = ["virt-install", "--name", "my_domain", "--ram", 2048, "--vcpus", "10,cores=10",
                          "--os-type", "linux", "--virt-type", "kvm", "--pxe", "--boot", "network,hd",
                          "--noautoconsole", "--graphics", "vnc,listen=0.0.0.0", "--autostart", "--disk",
                          "path=/test/1,serial=101,cache=none,bus=virtio", "--disk",
                          "path=/test/2,serial=102,cache=none,bus=virtio", "--network",
                          "network=pxe,mac=52:54:00:6d:38:8f,model=virtio", "--network",
                          "network=default,model=virtio"]
      expect(subject).to receive(:run).with(expected_command).and_return(['', true])
      subject.domain_create 'test', {
          'name' => 'my_domain',
          'cpu' => 10,
          'ram' => 2048,
          'networks' => [
              {
                  'network' => 'pxe',
                  'mac' => '52:54:00:6d:38:8f',
              },
              {
                  'network' => 'default',
              },
          ],
          'volumes' => [
              {
                  'path' => '/test/1',
                  'name' => 'test1_os',
                  'size' => 1,
                  'serial' => 101,
              },
              {
                  'path' => '/test/2',
                  'name' => 'test1_app',
                  'size' => 1,
                  'serial' => 102,
              },
          ],
      }
    end

  end

  context 'lists' do

    let(:virsh_list) do
      <<-eof
 Id    Name                           State
----------------------------------------------------
 408   vj884x_env_slave-15            running
 409   vj884x_env_slave-14            running
 410   vj884x_env_slave-13            running
 411   vj884x_env_slave-12            running
 -     ap943g_slave-02                shut off
 -     ap943g_slave-03                shut off
 -     ap943g_slave-04                shut off
 409   vj884x_env_slave-14            running
 410   vj884x_env_slave-13            running
 411   vj884x_env_slave-12            running
 412   vj884x_env_slave-11            running
      eof
    end

    let(:domain_list) do
      {
          "vj884x_env_slave-15"=>{"state"=>"running", "id"=>"408"},
          "vj884x_env_slave-14"=>{"state"=>"running", "id"=>"409"},
          "vj884x_env_slave-13"=>{"state"=>"running", "id"=>"410"},
          "vj884x_env_slave-12"=>{"state"=>"running", "id"=>"411"},
          "ap943g_slave-02"=>{"state"=>"shut off"},
          "ap943g_slave-03"=>{"state"=>"shut off"},
          "ap943g_slave-04"=>{"state"=>"shut off"},
          "vj884x_env_slave-11"=>{"state"=>"running", "id"=>"412"}}
    end

    let(:virsh_vol_list) do
      <<-eof
 Name                 Path
------------------------------------------------------------------------------
 _lab5.65.2016-08-02_13-39-17_admin-iso /var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_admin-iso
 _lab5.65.2016-08-02_13-39-17_admin-system /var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_admin-system
 _lab5.65.2016-08-02_13-39-17_slave-01-cinder /var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-01-cinder
 _lab5.65.2016-08-02_13-39-17_slave-01-swift /var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-01-swift
 _lab5.65.2016-08-02_13-39-17_slave-01-system /var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-01-system
 lab5.65.2016-08-02_13-39-17_slave-02-cinder /var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-02-cinder
 lab5.65.2016-08-02_13-39-17_slave-02-swift /var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-02-swift
 lab5.65.2016-08-02_13-39-17_slave-02-system /var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-02-system
      eof
    end

    let(:volume_list) do
      {
          "_lab5.65.2016-08-02_13-39-17_admin-iso"=>"/var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_admin-iso",
          "_lab5.65.2016-08-02_13-39-17_admin-system"=>"/var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_admin-system",
          "_lab5.65.2016-08-02_13-39-17_slave-01-cinder"=>"/var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-01-cinder",
          "_lab5.65.2016-08-02_13-39-17_slave-01-swift"=>"/var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-01-swift",
          "_lab5.65.2016-08-02_13-39-17_slave-01-system"=>"/var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-01-system",
          "lab5.65.2016-08-02_13-39-17_slave-02-cinder"=>"/var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-02-cinder",
          "lab5.65.2016-08-02_13-39-17_slave-02-swift"=>"/var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-02-swift",
          "lab5.65.2016-08-02_13-39-17_slave-02-system"=>"/var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_slave-02-system",
      }
    end

    let(:pool_name) { 'default' }

    it 'can get a list of domains' do
      expect(subject).to receive(:run).with(%w(virsh list --all)).exactly(1).times.and_return([virsh_list, true])
      expect(subject.domain_list).to eq domain_list
    end

    it 'can check that domain exists' do
      expect(subject).to receive(:run).with(%w(virsh list --all)).exactly(2).times.and_return([virsh_list, true])
      expect(subject.domain_defined? 'X').to eq false
      expect(subject.domain_defined? 'ap943g_slave-02').to eq true
    end

    it 'can get the domain status' do
      expect(subject).to receive(:run).with(%w(virsh list --all)).exactly(2).times.and_return([virsh_list, true])
      expect(subject.domain_state 'X').to eq 'missing'
      expect(subject.domain_state 'ap943g_slave-02').to eq 'shut off'
    end

    it 'can check if domain is running' do
      expect(subject).to receive(:run).with(%w(virsh list --all)).exactly(3).times.and_return([virsh_list, true])
      expect(subject.domain_started? 'X').to eq false
      expect(subject.domain_started? 'ap943g_slave-02').to eq false
      expect(subject.domain_started? 'vj884x_env_slave-11').to eq true
    end

    it 'can get a list of volumes' do
      expect(subject).to receive(:run).with(['virsh', 'vol-list', '--pool', pool_name]).exactly(1).times.and_return([virsh_vol_list, true])
      expect(subject.volume_list(pool_name)).to eq volume_list
    end

    it 'can get the volume path' do
      expect(subject).to receive(:run).with(['virsh', 'vol-list', '--pool', pool_name]).exactly(2).times.and_return([virsh_vol_list, true])
      expect(subject.volume_path('_lab5.65.2016-08-02_13-39-17_admin-iso', pool_name)).to eq '/var/lib/libvirt/images/_lab5.65.2016-08-02_13-39-17_admin-iso'
      expect(subject.volume_path('X', pool_name)).to eq nil
    end

    it 'can check that volume is defined' do
      expect(subject).to receive(:run).with(['virsh', 'vol-list', '--pool', pool_name]).exactly(2).times.and_return([virsh_vol_list, true])
      expect(subject.volume_defined?('_lab5.65.2016-08-02_13-39-17_admin-iso', pool_name)).to eq true
      expect(subject.volume_defined?('X', pool_name)).to eq false
    end

  end
end
