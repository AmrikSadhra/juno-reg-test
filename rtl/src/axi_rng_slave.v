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
`timescale 1ns / 1ps

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
    reg  [31:0] latched_wdata;
    reg  [7:0]  latched_wstrb;

    // State machine states
    reg [1:0] read_state;
    reg [2:0] write_state;

    localparam READ_IDLE     = 2'b00;
    localparam READ_DECODE   = 2'b01;
    localparam READ_RESPOND  = 2'b10;

    localparam WRITE_IDLE    = 3'b000;
    localparam WRITE_ADDR    = 3'b001;
    localparam WRITE_DATA    = 3'b010;
    localparam WRITE_EXEC    = 3'b011;
    localparam WRITE_RESP    = 3'b100;

    // RNG instance
    lfsr u_rng (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .read_enable(1'b1),
        .random_data(random_data)
    );

    //=========================================================================
    // READ CHANNEL STATE MACHINE
    //=========================================================================
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            ARREADY        <= 1'b0;
            RID            <= 16'h0;
            RDATA          <= 32'h0;
            RRESP          <= 2'b00;
            RLAST          <= 1'b0;
            RVALID         <= 1'b0;
            latched_arid   <= 16'h0;
            latched_araddr <= 32'h0;
            read_count     <= 32'h0;
            read_state     <= READ_IDLE;
        end else begin
            case (read_state)
                READ_IDLE: begin
                    ARREADY <= 1'b0;
                    RVALID  <= 1'b0;
                    RLAST   <= 1'b0;

                    if (ARVALID) begin
                        // Accept address
                        ARREADY        <= 1'b1;
                        latched_arid   <= ARID;
                        latched_araddr <= ARADDR;
                        read_state     <= READ_DECODE;
                    end
                end

                READ_DECODE: begin
                    ARREADY <= 1'b0;

                    // Decode address and prepare response
                    RID   <= latched_arid;
                    RLAST <= 1'b1;

                    // Check if address is within valid range (0x000-0x00F)
                    if (latched_araddr[23:4] == 4'h0) begin
                        case (latched_araddr[3:2])
                            2'h0: begin // 0x000: RNG data
                                RDATA <= random_data;
                                RRESP <= 2'b00;
                                read_count <= read_count + 32'd1;
                            end
                            2'h1: begin // 0x004: Control register
                                RDATA <= control_reg;
                                RRESP <= 2'b00;
                            end
                            2'h2: begin // 0x008: Seed register
                                RDATA <= seed_reg;
                                RRESP <= 2'b00;
                            end
                            2'h3: begin // 0x00C: Read counter
                                RDATA <= read_count;
                                RRESP <= 2'b00;
                            end
                        endcase
                    end else begin
                        // Out of range - return error
                        RDATA <= 32'hDEADBEEF;
                        RRESP <= 2'b10; // SLVERR
                    end

                    RVALID     <= 1'b1;
                    read_state <= READ_RESPOND;
                end

                READ_RESPOND: begin
                    if (RREADY) begin
                        // Master accepted data
                        RVALID     <= 1'b0;
                        RLAST      <= 1'b0;
                        read_state <= READ_IDLE;
                    end
                    // Otherwise stay in this state until master is ready
                end

                default: begin
                    read_state <= READ_IDLE;
                end
            endcase
        end
    end

    //=========================================================================
    // WRITE CHANNEL STATE MACHINE
    //=========================================================================
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            AWREADY        <= 1'b0;
            WREADY         <= 1'b0;
            BID            <= 16'h0;
            BRESP          <= 2'b00;
            BVALID         <= 1'b0;
            latched_awid   <= 16'h0;
            latched_awaddr <= 32'h0;
            latched_wdata  <= 32'h0;
            latched_wstrb  <= 8'h0;
            control_reg    <= 32'h0;
            seed_reg       <= 32'hACE1;
            write_state    <= WRITE_IDLE;
        end else begin
            case (write_state)
                WRITE_IDLE: begin
                    AWREADY <= 1'b0;
                    WREADY  <= 1'b0;
                    BVALID  <= 1'b0;

                    // Wait for either address or data first
                    if (AWVALID && WVALID) begin
                        // Both arrive together
                        AWREADY        <= 1'b1;
                        WREADY         <= 1'b1;
                        latched_awid   <= AWID;
                        latched_awaddr <= AWADDR;
                        latched_wdata  <= WDATA;
                        latched_wstrb  <= WSTRB;
                        write_state    <= WRITE_EXEC;
                    end else if (AWVALID) begin
                        // Address arrives first
                        AWREADY        <= 1'b1;
                        latched_awid   <= AWID;
                        latched_awaddr <= AWADDR;
                        write_state    <= WRITE_DATA;
                    end else if (WVALID) begin
                        // Data arrives first
                        WREADY        <= 1'b1;
                        latched_wdata <= WDATA;
                        latched_wstrb <= WSTRB;
                        write_state   <= WRITE_ADDR;
                    end
                end

                WRITE_ADDR: begin
                    // Waiting for address (already have data)
                    WREADY <= 1'b0;

                    if (AWVALID) begin
                        AWREADY        <= 1'b1;
                        latched_awid   <= AWID;
                        latched_awaddr <= AWADDR;
                        write_state    <= WRITE_EXEC;
                    end
                end

                WRITE_DATA: begin
                    // Waiting for data (already have address)
                    AWREADY <= 1'b0;

                    if (WVALID) begin
                        WREADY        <= 1'b1;
                        latched_wdata <= WDATA;
                        latched_wstrb <= WSTRB;
                        write_state   <= WRITE_EXEC;
                    end
                end

                WRITE_EXEC: begin
                    // Execute the write
                    AWREADY <= 1'b0;
                    WREADY  <= 1'b0;

                    // Check if address is within valid range (0x000-0x00F)
                    if (latched_awaddr[23:4] == 4'h0) begin
                        case (latched_awaddr[3:2])
                            2'h0: begin // 0x000: RNG data (read-only)
                                BRESP <= 2'b00; // OKAY but ignored
                            end
                            2'h1: begin // 0x004: Control register
                                if (latched_wstrb[0]) control_reg[7:0]   <= latched_wdata[7:0];
                                if (latched_wstrb[1]) control_reg[15:8]  <= latched_wdata[15:8];
                                if (latched_wstrb[2]) control_reg[23:16] <= latched_wdata[23:16];
                                if (latched_wstrb[3]) control_reg[31:24] <= latched_wdata[31:24];
                                BRESP <= 2'b00;
                            end
                            2'h2: begin // 0x008: Seed register
                                if (latched_wstrb[0]) seed_reg[7:0]   <= latched_wdata[7:0];
                                if (latched_wstrb[1]) seed_reg[15:8]  <= latched_wdata[15:8];
                                if (latched_wstrb[2]) seed_reg[23:16] <= latched_wdata[23:16];
                                if (latched_wstrb[3]) seed_reg[31:24] <= latched_wdata[31:24];
                                BRESP <= 2'b00;
                            end
                            2'h3: begin // 0x00C: Read counter (read-only)
                                BRESP <= 2'b00; // OKAY but ignored
                            end
                        endcase
                    end else begin
                        // Out of range - return error
                        BRESP <= 2'b10; // SLVERR
                    end

                    BID         <= latched_awid;
                    BVALID      <= 1'b1;
                    write_state <= WRITE_RESP;
                end

                WRITE_RESP: begin
                    if (BREADY) begin
                        // Master accepted response
                        BVALID      <= 1'b0;
                        write_state <= WRITE_IDLE;
                    end
                    // Otherwise stay in this state
                end

                default: begin
                    write_state <= WRITE_IDLE;
                end
            endcase
        end
    end

endmodule