# ARM Juno Register Test

A C++ application for fun, providing low-level access to a couple of interesting exposed registers documented in the Juno r1 Technical Reference Manual.

## Features

- **Hardware Register Access**: Direct memory-mapped I/O access to Juno board registers, including example code that utilises a spare AXI Slave port on the CoreLink-NIC400 [ThinLinks]. Example RTL for this to follow.
- **Board Information**: System identification and hardware version detection

## Hardware Support

This project targets any revision of the ARM Juno development board, as well as any associated LogicTile.

## Prerequisites

- ARM Juno development board
- Linux build environment with root access and GCC/LLVM

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
- `-r`: Run RNG test sequence
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
