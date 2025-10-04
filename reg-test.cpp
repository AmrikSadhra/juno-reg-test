#include <cstring>
#include <iostream>
#include <iomanip>
#include <string>
#include <map>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <cstdint>
#include <stdexcept>
#include <array>
#include <chrono>
#include <thread>

#include "enum.h"
#include "bitmanip.hpp"
#include <random>

// NOTE: These must be page-aligned addresses for mmap.
constexpr uint64_t SCC_BASE_ADDR{0x60010000}; // System Control Controller
constexpr uint64_t APB_BASE_ADDR{0x1C010000}; // Juno Advanced Peripheral Bus
constexpr uint64_t AXI_BASE_ADDR{0x64000000}; // LogicTile Spare AXI Slave

// The size of the memory region to map. We map one standard page (4KB) to ensure we cover most registers around the base address.
constexpr size_t MAP_SIZE{4096}; // 4KB, standard page size

BETTER_ENUM(SCCRegister, uint32_t,
            SCC_LED = 0x104
)

BETTER_ENUM(APBRegister, uint32_t,
            SYS_ID = 0x000,
            SYS_SQ = 0x004,
            SYS_LED = 0x008,
            SYS_100HZ = 0x0024,
            SYS_FLAG = 0x0030,
            SYS_FLAGSCLR = 0x0034,
            SYS_NVFLAGS = 0x0038,
            SYS_NVFLAGSCLR = 0x003C,
            SYS_CFGSW = 0x0058,
            SYS_24MHZ = 0x005C,
            SYS_MISC = 0x0060,
            SYS_PCIE_CNTL = 0x0070,
            SYS_PCIE_GBE_L = 0x0074,
            SYS_PCIE_GBE_H = 0x0078,
            SYS_PROC_ID0 = 0x0084,
            SYS_PROC_ID1 = 0x0088,
            SYS_FAN_SPEED = 0x0120)

BETTER_ENUM(AXIRegister, uint32_t,
            AMS_RNGDATA = 0x000,
            AMS_RNGCTRL = 0x004,
            AMS_RNGSEED = 0x008,
            AMS_RNGCNT = 0x00C)

/**
 * @brief Manages memory mapping and provides read/write access to hardware registers.
 *
 * This class handles opening /dev/mem and mapping the physical base address
 * into the process's virtual memory space.
 */
class RegisterManager
{
private:
    int m_fd{-1};
    void *m_map_base{nullptr};
    const uint64_t m_physical_base;
    const bool m_logging;

public:
    /**
     * @brief Constructor: Initializes the memory map.
     * @param physical_base The starting physical address to map.
     * @param logging Whether to log accesses to stdout
     */
    RegisterManager(uint64_t const physical_base, bool const logging) : m_physical_base(physical_base), m_logging(logging)
    {
        m_fd = open("/dev/mem", O_RDWR | O_SYNC);
        if (m_fd == -1)
        {
            throw std::runtime_error("Error: Could not open /dev/mem. Must run as root or with appropriate permissions.");
        }

        // 2. Map the physical address range into virtual memory
        m_map_base = mmap(
            0,                      // addr: Let the kernel choose the address
            MAP_SIZE,               // len: The size of the memory region
            PROT_READ | PROT_WRITE, // prot: Read/Write access
            MAP_SHARED,             // flags: Share changes with other processes/hardware
            m_fd,                   // fd: File descriptor for /dev/mem
            m_physical_base         // offset: The physical address start
        );

        if (m_map_base == MAP_FAILED)
        {
            close(m_fd);
            throw std::runtime_error("Error: mmap failed to map physical address.");
        }

        std::cout << "[INFO] Successfully mapped physical address 0x" << std::hex
                  << m_physical_base << " to virtual address " << m_map_base << std::dec << std::endl;
    }

    /**
     * @brief Destructor: Cleans up the memory map and file descriptor.
     */
    ~RegisterManager()
    {
        if (m_map_base != MAP_FAILED && m_map_base != nullptr)
        {
            if (munmap(m_map_base, MAP_SIZE) == -1)
            {
                std::cerr << "[ERROR] Failed to unmap memory." << std::endl;
            }
            else
            {
                std::cout << "[INFO] Memory unmapped successfully." << std::endl;
            }
        }
        if (m_fd != -1)
        {
            close(m_fd);
        }
    }

    /**
     * @brief Reads a 32-bit value from a register offset.
     * @param reg Register enum which encodes it's offset from the base address.
     * @return The 32-bit value read from the register.
     */
    template <typename T>
    uint32_t readReg(T const &reg) const
    {
        if (!m_map_base)
        {
            std::cerr << "[ERROR] Cannot read: memory not mapped." << std::endl;
            return 0;
        }
        uint32_t const offset{static_cast<uint32_t>(reg)};
        volatile uint32_t *reg_ptr{(volatile uint32_t *)((char *)m_map_base + offset)};
        uint32_t const value{*reg_ptr};

        if (m_logging)
        {
            std::cout << "  > Read 0x" << std::hex << std::setw(8) << std::setfill('0') << value
                      << " from register " << (+reg)._to_string() << " (base 0x" << m_physical_base << " + offset 0x" << offset << std::dec << ")" << std::endl;
        }
        return value;
    }

    /**
     * @brief Writes a 32-bit value to a register offset.
     * @param reg Register enum which encodes it's offset from the base address.
     * @param value The 32-bit value to write.
     */
    template <typename T>
    void writeReg(T const &reg, uint32_t value) const
    {
        if (!m_map_base)
        {
            std::cerr << "[ERROR] Cannot write: memory not mapped." << std::endl;
            return;
        }
        uint32_t const offset{static_cast<uint32_t>(reg)};
        volatile uint32_t *reg_ptr{(volatile uint32_t *)((char *)m_map_base + offset)};

        if (m_logging)
        {
            std::cout << "  > Writing 0x" << std::hex << std::setw(8) << std::setfill('0') << value
                      << " to register " << (+reg)._to_string() << " (base 0x" << m_physical_base << " offset 0x" << offset << std::dec << ")" << std::endl;
        }
        *reg_ptr = value;
    }
};

[[nodiscard]] static std::string get_board_info(uint32_t const sys_id_reg_val)
{
    std::stringstream board_info;
    uint32_t const rev{extract_bits(sys_id_reg_val, 28, 4)};
    uint32_t const hbi{extract_bits(sys_id_reg_val, 16, 10)};
    uint32_t const build{extract_bits(sys_id_reg_val, 12, 3)};
    uint32_t const arch{extract_bits(sys_id_reg_val, 8, 3)};
    uint32_t const fpga{extract_bits(sys_id_reg_val, 0, 7)};

    std::string board_revision;
    switch (rev)
    {
    case 0x0:
        board_revision = "Rev A (Prototype Juno r0)";
        break;
    case 0x1:
        board_revision = "Rev B (Juno r0)";
        break;
    case 0x2:
        board_revision = "Rev C (Juno r1)";
        break;
    case 0x3:
        board_revision = "Rev D (Juno r2)";
        break;
    default:
        board_revision = "Unknown";
        break;
    }

    board_info << board_revision << " HBI" << std::hex << hbi << ", Board Build Variant: " << build << ", IOFPGA Bus Arch: " << (arch == 0x4 ? "AHB" : "AXI") << ", FPGA Build (BCD): " << fpga;

    return board_info.str();
}

[[nodiscard]] static std::string get_logictile_info(uint32_t const sys_proc_id_1_val)
{
    std::stringstream board_info;
    uint32_t const app_note{extract_bits(sys_proc_id_1_val, 24, 8)};
    uint32_t const rev{extract_bits(sys_proc_id_1_val, 20, 4)};
    uint32_t const var{extract_bits(sys_proc_id_1_val, 16, 4)};
    uint32_t const hbi{extract_bits(sys_proc_id_1_val, 0, 12)};

    char const board_rev {static_cast<char>(rev + 'A')};
    char const board_variant {static_cast<char>(var + 'A')};

    board_info << "FPGA Image: " << app_note << ", Board Revision: " << board_rev << ", Board Build Variant: " << board_variant << ", HBI" << std::hex << hbi;

    return board_info.str();
}

void logictile_led_test_sequence(RegisterManager const &scc_reg_access)
{
    // LED Animation Sequences
    std::cout << "\n[LED Animation] Starting light show..." << std::endl;

    // 1. Knight Rider / Cylon scanner effect
    std::cout << "[LED Animation] Knight Rider sweep..." << std::endl;
    for (int i = 0; i < 8; ++i)
    {
        scc_reg_access.writeReg(SCCRegister::SCC_LED, 1 << i);
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    for (int i = 6; i >= 1; --i)
    {
        scc_reg_access.writeReg(SCCRegister::SCC_LED, 1 << i);
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    // 2. Binary counter
    std::cout << "[LED Animation] Binary counter..." << std::endl;
    for (uint32_t i = 0; i < 256; ++i)
    {
        scc_reg_access.writeReg(SCCRegister::SCC_LED, i);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    // 3. Outward expansion from center
    std::cout << "[LED Animation] Outward expansion..." << std::endl;
    std::array<uint32_t, 5> expand_patterns = {
        0b00011000,
        0b00111100,
        0b01111110,
        0b11111111,
        0b00000000};
    for (int repeat = 0; repeat < 3; ++repeat)
    {
        for (auto const &pattern : expand_patterns)
        {
            scc_reg_access.writeReg(SCCRegister::SCC_LED, pattern);
            std::this_thread::sleep_for(std::chrono::milliseconds(150));
        }
    }

    // 4. Alternating chase
    std::cout << "[LED Animation] Alternating chase..." << std::endl;
    for (int i = 0; i < 8; ++i)
    {
        scc_reg_access.writeReg(SCCRegister::SCC_LED, 0b10101010);
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        scc_reg_access.writeReg(SCCRegister::SCC_LED, 0b01010101);
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    // 5. Inward collapse
    std::cout << "[LED Animation] Inward collapse..." << std::endl;
    std::array<uint32_t, 5> collapse_patterns = {
        0b11111111,
        0b01111110,
        0b00111100,
        0b00011000,
        0b00000000};
    for (int repeat = 0; repeat < 3; ++repeat)
    {
        for (auto const &pattern : collapse_patterns)
        {
            scc_reg_access.writeReg(SCCRegister::SCC_LED, pattern);
            std::this_thread::sleep_for(std::chrono::milliseconds(150));
        }
    }

    // 6. Random sparkle
    std::cout << "[LED Animation] Random sparkle..." << std::endl;
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<> distrib(0, 255);
    for (int i = 0; i < 30; ++i)
    {
        scc_reg_access.writeReg(SCCRegister::SCC_LED, distrib(gen));
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    // 7. Wave effect (moving single LED with trail)
    std::cout << "[LED Animation] Wave effect..." << std::endl;
    for (int cycle = 0; cycle < 2; ++cycle)
    {
        for (int i = 0; i < 8; ++i)
        {
            uint32_t pattern = (1 << i);
            if (i > 0)
                pattern |= (1 << (i - 1));
            if (i > 1)
                pattern |= (1 << (i - 2));
            scc_reg_access.writeReg(SCCRegister::SCC_LED, pattern);
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }

    // 8. Finale - all flash
    std::cout << "[LED Animation] Grand finale!" << std::endl;
    for (int i = 0; i < 5; ++i)
    {
        scc_reg_access.writeReg(SCCRegister::SCC_LED, 0b11111111);
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        scc_reg_access.writeReg(SCCRegister::SCC_LED, 0b00000000);
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    // All off
    scc_reg_access.writeReg(SCCRegister::SCC_LED, 0b00000000);
    std::cout << "[LED Animation] Show complete!" << std::endl;
}

void axi_slave_rng_test_sequence(RegisterManager const &axi_reg_access)
{
    std::cout << "AXI Slave RNG Peripheral Test:" << std::endl;
    uint32_t const rnd_count_expected{10};
    for (uint32_t rnd_count{0}; rnd_count < rnd_count_expected; ++rnd_count)
    {
        uint32_t const rnd{axi_reg_access.readReg(AXIRegister::AMS_RNGDATA)};
        std::cout << "RNGDATA Read " << rnd_count << ": " << std::hex << rnd << std::endl;
    }
    uint32_t const rng_readcnt{axi_reg_access.readReg(AXIRegister::AMS_RNGCNT)};
    std::cout << "RNGCNT Indicates RNGDATA Read " << std::dec << rng_readcnt << " Times" << std::endl;
    if (rng_readcnt != rnd_count_expected)
    {
        std::cout << "RNG READCNT Test failed" << std::endl;
    }

    uint32_t const rng_seed{0xCAFEBABE};
    axi_reg_access.writeReg(AXIRegister::AMS_RNGSEED, rng_seed);
    uint32_t const rng_seed_read{axi_reg_access.readReg(AXIRegister::AMS_RNGSEED)};
    if (rng_seed_read == rng_seed)
    {
        std::cout << "RNG Seed Write Test succeeded" << std::endl;
    } else 
    {
        std::cerr << "RNG SEED Write Test failed" << std::endl;
    }
}

void print_usage(char const *program_name)
{
    std::cout << "Usage: " << program_name << " [OPTIONS]\n"
              << "Options:\n"
              << "  -v         Enable verbose logging of register accesses\n"
              << "  -l         Run LED test sequence\n"
              << "  -r         Run RNG test sequence\n"
              << "  -h         Display this help message\n"
              << std::endl;
}

int main(int argc, char *argv[])
{
    bool verbose{false};
    bool run_led_test{false};
    bool run_rng_test{false};
    int opt;

    // Parse command-line arguments
    while ((opt = getopt(argc, argv, "vlrh")) != -1)
    {
        switch (opt)
        {
        case 'v':
            verbose = true;
            break;
        case 'l':
            run_led_test = true;
            break;
        case 'r':
            run_rng_test = true;
            break;
        case 'h':
            print_usage(argv[0]);
            return 0;
        default:
            print_usage(argv[0]);
            return 1;
        }
    }

    try
    {
        RegisterManager scc_reg_access(SCC_BASE_ADDR, verbose);
        RegisterManager apb_reg_access(APB_BASE_ADDR, verbose);
        RegisterManager axi_reg_access(AXI_BASE_ADDR, verbose);

        std::cout << "ARM Juno Platform Information:" << get_board_info(apb_reg_access.readReg(APBRegister::SYS_ID)) << std::endl;
        std::cout << "LogicTile Information:" << get_logictile_info(apb_reg_access.readReg(APBRegister::SYS_PROC_ID1)) << std::endl;                  
                  
        if (run_rng_test)
        {
            axi_slave_rng_test_sequence(axi_reg_access);
        }
        if (run_led_test)
        {
            logictile_led_test_sequence(scc_reg_access);
        }
    }
    catch (const std::runtime_error &e)
    {
        std::cerr << "\n[FATAL ERROR] " << e.what() << std::endl;
        std::cerr << "Please ensure you have necessary permissions (e.g., run with 'sudo') and the physical address is correct." << std::endl;
        return 1;
    }
    
    return 0;
}