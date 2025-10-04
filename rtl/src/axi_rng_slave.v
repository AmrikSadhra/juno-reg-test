`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.10.2025 09:38:02
// Design Name: 
// Module Name: axi_rng_slave
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module axi_rng_slave (
    // Global signals
    input  wire        ACLK,
    input  wire        ARESETn,

    // AXI Read Address Channel
    input  wire [15:0] ARID,
    input  wire [31:0] ARADDR,
    input  wire [3:0]  ARLEN,
    input  wire [2:0]  ARSIZE,
    input  wire [1:0]  ARBURST,
    input  wire        ARVALID,
    output reg         ARREADY,

    // AXI Read Data Channel
    output reg  [15:0] RID,
    output reg  [31:0] RDATA,
    output reg  [1:0]  RRESP,
    output reg         RLAST,
    output reg         RVALID,
    input  wire        RREADY,

    // AXI Write Address Channel
    input  wire [15:0] AWID,
    input  wire [31:0] AWADDR,
    input  wire [3:0]  AWLEN,
    input  wire [2:0]  AWSIZE,
    input  wire [1:0]  AWBURST,
    input  wire        AWVALID,
    output reg         AWREADY,

    // AXI Write Data Channel
    input  wire [31:0] WDATA,
    input  wire [7:0]  WSTRB,
    input  wire        WVALID,
    output reg         WREADY,

    // AXI Write Response Channel
    output reg  [15:0] BID,
    output reg  [1:0]  BRESP,
    output reg         BVALID,
    input  wire        BREADY
);

    // Internal registers
    wire [31:0] random_data;
    reg  [31:0] control_reg; // 0x004: Control register
    reg  [31:0] seed_reg; // 0x008: Seed register
    reg  [31:0] read_count; // 0x00C: Read counter

    reg  [15:0] latched_arid;
    reg  [31:0] latched_araddr;
    reg  [15:0] latched_awid;
    reg  [31:0] latched_awaddr;
    reg         write_addr_valid;
    reg         write_data_valid;

    // RNG instance
    lfsr u_rng (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .read_enable(1'b1),
        .random_data(random_data)
    );

    // Read channel logic
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            ARREADY      <= 1'b0;
            RID          <= 16'h0;
            RDATA        <= 32'h0;
            RRESP        <= 2'b00;
            RLAST        <= 1'b0;
            RVALID       <= 1'b0;
            latched_arid <= 16'h0;
            latched_araddr <= 32'h0;
            read_count   <= 32'h0;
        end else begin
            // Accept read address and latch ID and address
            if (ARVALID && !ARREADY) begin
                ARREADY        <= 1'b1;
                latched_arid   <= ARID;
                latched_araddr <= ARADDR;
            end else begin
                ARREADY <= 1'b0;
            end

            // Provide read data with address decoding
            if (ARREADY && !RVALID) begin
                RID    <= latched_arid;
                RLAST  <= 1'b1;
                RVALID <= 1'b1;

                // Address decode - only look at low address bits
                case (latched_araddr[7:2]) // Word-aligned addresses
                    6'h00: begin // 0x000: RNG data register
                        RDATA <= random_data;
                        RRESP <= 2'b00; // OKAY
                        read_count <= read_count + 1;
                    end
                    6'h01: begin // 0x004: Control register
                        RDATA <= control_reg;
                        RRESP <= 2'b00; // OKAY
                    end
                    6'h02: begin // 0x008: Seed register
                        RDATA <= seed_reg;
                        RRESP <= 2'b00; // OKAY
                    end
                    6'h03: begin // 0x00C: Read counter
                        RDATA <= read_count;
                        RRESP <= 2'b00; // OKAY
                    end
                    default: begin // Unmapped addresses
                        RDATA <= 32'hDEADBEEF;
                        RRESP <= 2'b10; // SLVERR - Slave error
                    end
                endcase
            end else if (RVALID && RREADY) begin
                RVALID <= 1'b0;
                RLAST  <= 1'b0;
            end
        end
    end
       
    // Write channel logic
    always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
        AWREADY          <= 1'b0;
        WREADY           <= 1'b0;
        BID              <= 16'h0;
        BRESP            <= 2'b00;
        BVALID           <= 1'b0;
        latched_awid     <= 16'h0;
        latched_awaddr   <= 32'h0;
        write_addr_valid <= 1'b0;
        write_data_valid <= 1'b0;
        control_reg      <= 32'h0;
        seed_reg         <= 32'hACE1;
    end else begin
        // Always accept address when valid
        if (AWVALID && !write_addr_valid) begin
            AWREADY        <= 1'b1;
            latched_awid   <= AWID;
            latched_awaddr <= AWADDR;
            write_addr_valid <= 1'b1;
        end else begin
            AWREADY <= 1'b0;
        end
        
        // Always accept data when valid  
        if (WVALID && !write_data_valid) begin
            WREADY <= 1'b1;
            write_data_valid <= 1'b1;
        end else begin
            WREADY <= 1'b0;
        end
        
        // When both are valid, perform the write
        if (write_addr_valid && write_data_valid && !BVALID) begin
            // Perform write based on address
            case (latched_awaddr[7:2])
                6'h01: begin  // Control register
                    if (WSTRB[0]) control_reg[7:0]   <= WDATA[7:0];
                    if (WSTRB[1]) control_reg[15:8]  <= WDATA[15:8];
                    if (WSTRB[2]) control_reg[23:16] <= WDATA[23:16];
                    if (WSTRB[3]) control_reg[31:24] <= WDATA[31:24];
                    BRESP <= 2'b00;
                end
                6'h02: begin  // Seed register
                    if (WSTRB[0]) seed_reg[7:0]   <= WDATA[7:0];
                    if (WSTRB[1]) seed_reg[15:8]  <= WDATA[15:8];
                    if (WSTRB[2]) seed_reg[23:16] <= WDATA[23:16];
                    if (WSTRB[3]) seed_reg[31:24] <= WDATA[31:24];
                    BRESP <= 2'b00;
                end
                6'h00, 6'h03: BRESP <= 2'b00;  // Read-only, but respond OK
                default: BRESP <= 2'b10;  // SLVERR
            endcase
            
            BID    <= latched_awid;
            BVALID <= 1'b1;
            write_addr_valid <= 1'b0;
            write_data_valid <= 1'b0;
        end else if (BVALID && BREADY) begin
            BVALID <= 1'b0;
        end
    end
end

endmodule