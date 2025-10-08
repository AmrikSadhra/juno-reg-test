# ARM Juno Register Test

A quick and fun demo project providing low-level access to a couple of interesting exposed registers documented in the Juno r1 Technical Reference Manual.

Example AXI Slave port RTL to demonstrate integration of peripherals within the AN415 memory subsystem is supplied, and this is shown to be programmable from Linux userspace with example code.

## Features

- **Hardware Register Access**: Direct memory-mapped I/O access to Juno board registers, including example code that utilises a spare AXI Slave port on the CoreLink-NIC400 (ThinLinks). 
- **AXI Slave Port Example RTL**: An AXI Compliant slave-port implementation is supplied alongside a memory-mapped LFSR peripheral. 
- **Board Information**: System identification and hardware version detection

## Hardware Support

This project targets any revision of the ARM Juno development board, as well as any associated LogicTile.

## Prerequisites

- ARM Juno development board
- Linux C++ build environment with root access 

## Project Structure

```
- reg-test.cpp (This program)
- rtl
   |- sim (Testbench for AXI Slave)
   |- src (Synthesisable RTL for AXI Slave)
```

## Building

```bash
# Build the project
make

# Build and run all tests with verbose output
make run-all

# Clean build artifacts
make clean
```

## Usage

## Hardware

Any interaction with the RNG peripheral on the AXI Slave Port mapping requires the corresponding RTL to be patched into the Arm-supplied [AN415](https://developer.arm.com/downloads/view/VEJ20)
FPGA top level wrapper. 

1. Replace the `EgSlaveAxi` module in `an414_toplevel.v` with an instantiation of the `rng_axi_slave` module supplied at `rtl/src`. The ports are the exact same, excluding 
some buses that were tied off (`SCAN<X>, C<ACTIVE/SYS>` etc) - these can be safely removed from the instantiation.
2. Run behavioural simulation of the `rng_axi_slave_tb` and ensure all tests pass.
3. Synthesise the design and generate the bitfile, then replace `SITE2/HBI0247C/AN415/a415r0p1.bit` on the configuration micro-SD card with your updated version.
4. Reboot the Juno, and the bitfile should successfully be programmed.

## Software

The program requires root privileges to access `/dev/mem` for hardware register access:

```bash
# Basic usage - display board information
sudo ./reg-test

# Run all tests with verbose output
sudo ./reg-test -v -l -r

# Display help
./reg-test -h
```

### Command Line Options

- `-v`: Enable verbose logging of register accesses
- `-l`: Run LED test sequence with various animation patterns
- `-r`: Run RNG test sequence, testing a peripheral at the base of the new AXI Slave port
- `-h`: Display help message

## Key Components

### RegisterManager Class

Handles memory mapping and provides read/write access to hardware registers:

```cpp
RegisterManager scc_reg_access(SCC_BASE_ADDR, verbose);
uint32_t value = scc_reg_access.readReg(SCCRegister::SCC_LED);
scc_reg_access.writeReg(SCCRegister::SCC_LED, 0xFF);
```

## Safety Considerations

⚠️ **Warning**: This application performs direct hardware register access and should only be used on appropriate development hardware. Incorrect register access can potentially damage hardware.

- Ensure you're running on the correct hardware platform by verifying register addresses match your specific Juno board revision (they should!)

## Troubleshooting

### Permission Denied
```
Error: Could not open /dev/mem. Must run as root or with appropriate permissions.
```
**Solution**: Run with `sudo` or ensure your user has appropriate permissions for `/dev/mem`.
