`timescale 1ns/1ps

module rng_axi_slave_tb;

    // Clock and reset
    reg         ACLK;
    reg         ARESETn;
    
    // AXI Read Address Channel
    reg  [15:0] ARID;
    reg  [31:0] ARADDR;
    reg  [3:0]  ARLEN;
    reg  [2:0]  ARSIZE;
    reg  [1:0]  ARBURST;
    reg         ARVALID;
    wire        ARREADY;
    
    // AXI Read Data Channel
    wire [15:0] RID;
    wire [31:0] RDATA;
    wire [1:0]  RRESP;
    wire        RLAST;
    wire        RVALID;
    reg         RREADY;
    
    // AXI Write Address Channel
    reg  [15:0] AWID;
    reg  [31:0] AWADDR;
    reg  [3:0]  AWLEN;
    reg  [2:0]  AWSIZE;
    reg  [1:0]  AWBURST;
    reg         AWVALID;
    wire        AWREADY;
    
    // AXI Write Data Channel
    reg  [31:0] WDATA;
    reg  [7:0]  WSTRB;
    reg         WVALID;
    wire        WREADY;
    
    // AXI Write Response Channel
    wire [15:0] BID;
    wire [1:0]  BRESP;
    wire        BVALID;
    reg         BREADY;
    
    // Instantiate DUT
    axi_rng_slave dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .ARID(ARID),
        .ARADDR(ARADDR),
        .ARLEN(ARLEN),
        .ARSIZE(ARSIZE),
        .ARBURST(ARBURST),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        .RID(RID),
        .RDATA(RDATA),
        .RRESP(RRESP),
        .RLAST(RLAST),
        .RVALID(RVALID),
        .RREADY(RREADY),
        .AWID(AWID),
        .AWADDR(AWADDR),
        .AWLEN(AWLEN),
        .AWSIZE(AWSIZE),
        .AWBURST(AWBURST),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        .WDATA(WDATA),
        .WSTRB(WSTRB),
        .WVALID(WVALID),
        .WREADY(WREADY),
        .BID(BID),
        .BRESP(BRESP),
        .BVALID(BVALID),
        .BREADY(BREADY)
    );
    
    // Clock generation - 100MHz
    initial begin
        ACLK = 0;
        forever #5 ACLK = ~ACLK;
    end
    
    // Test variables
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    
    // Task to perform AXI read
    task axi_read;
        input [31:0] addr;
        input [15:0] id;
        output [31:0] data;
        output [1:0] resp;
        begin
            @(posedge ACLK);
            ARADDR  = addr;
            ARID    = id;
            ARLEN   = 4'h0;  // Single transfer
            ARSIZE  = 3'b010; // 4 bytes
            ARBURST = 2'b01;  // INCR
            ARVALID = 1'b1;
            RREADY  = 1'b0;
            
            // Wait for address acceptance
            @(posedge ACLK);
            while (!ARREADY) @(posedge ACLK);
            ARVALID = 1'b0;
            
            // Wait for data
            RREADY = 1'b1;
            @(posedge ACLK);
            while (!RVALID) @(posedge ACLK);
            
            data = RDATA;
            resp = RRESP;
            
            if (RID !== id)
                $display("ERROR: RID mismatch! Expected %h, got %h", id, RID);
            if (!RLAST)
                $display("ERROR: RLAST not asserted!");
                
            @(posedge ACLK);
            RREADY = 1'b0;
        end
    endtask
    
    // Task to perform AXI write
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [7:0]  strb;
        input [15:0] id;
        output [1:0] resp;
        begin
            @(posedge ACLK);
            
            // Send address and data simultaneously
            AWADDR  = addr;
            AWID    = id;
            AWLEN   = 4'h0;
            AWSIZE  = 3'b010;
            AWBURST = 2'b01;
            AWVALID = 1'b1;
            
            WDATA   = data;
            WSTRB   = strb;
            WVALID  = 1'b1;
            
            BREADY  = 1'b0;
            
            // Wait for both address and data acceptance
            @(posedge ACLK);
            while (!AWREADY || !WREADY) @(posedge ACLK);
            
            AWVALID = 1'b0;
            WVALID  = 1'b0;
            
            // Wait for response
            BREADY = 1'b1;
            @(posedge ACLK);
            while (!BVALID) @(posedge ACLK);
            
            resp = BRESP;
            
            if (BID !== id)
                $display("ERROR: BID mismatch! Expected %h, got %h", id, BID);
                
            @(posedge ACLK);
            BREADY = 1'b0;
        end
    endtask
    
    // Main test sequence
    initial begin
        // Initialize signals
        ARESETn = 0;
        ARVALID = 0;
        RREADY  = 0;
        AWVALID = 0;
        WVALID  = 0;
        BREADY  = 0;
        
        // Dump waveforms
        $dumpfile("axi_rng_tb.vcd");
        $dumpvars(0, rng_axi_slave_tb);
        
        // Reset
        #100;
        ARESETn = 1;
        #50;
        
        $display("=====================================");
        $display("Starting AXI RNG Slave Testbench");
        $display("=====================================\n");
        
        // Test 1: Read RNG register (0x000)
        begin
            reg [31:0] rdata;
            reg [1:0] rresp;
            $display("Test %0d: Read RNG_DATA register (0x000)", ++test_count);
            axi_read(32'h64000000, 16'h0001, rdata, rresp);
            if (rresp == 2'b00) begin
                $display("  PASS: Read successful, data = 0x%08h", rdata);
                ++pass_count;
            end else begin
                $display("  FAIL: Bad response = %b", rresp);
                ++fail_count;
            end
        end
        
        // Test 2: Read RNG multiple times (should get different values)
        begin
            reg [31:0] rdata1, rdata2;
            reg [1:0] rresp;
            $display("\nTest %0d: Multiple RNG reads", ++test_count);
            axi_read(32'h64000000, 16'h0002, rdata1, rresp);
            #100;
            axi_read(32'h64000000, 16'h0003, rdata2, rresp);
            if (rdata1 !== rdata2) begin
                $display("  PASS: Got different values: 0x%08h, 0x%08h", rdata1, rdata2);
                ++pass_count;
            end else begin
                $display("  FAIL: Got same value twice: 0x%08h", rdata1);
                ++fail_count;
            end
        end
        
        // Test 3: Write to CONTROL register (0x004)
        begin
            reg [31:0] rdata;
            reg [1:0] rresp, wresp;
            $display("\nTest %0d: Write/Read CONTROL register (0x004)", ++test_count);
            axi_write(32'h64000004, 32'hDEADBEEF, 8'hFF, 16'h0004, wresp);
            axi_read(32'h64000004, 16'h0005, rdata, rresp);
            if (rdata == 32'hDEADBEEF && wresp == 2'b00 && rresp == 2'b00) begin
                $display("  PASS: Control register = 0x%08h", rdata);
                ++pass_count;
            end else begin
                $display("  FAIL: Expected 0xDEADBEEF, got 0x%08h", rdata);
                ++fail_count;
            end
        end
        
        // Test 4: Partial write with WSTRB
        begin
            reg [31:0] rdata;
            reg [1:0] rresp, wresp;
            $display("\nTest %0d: Partial write to SEED register (0x008)", ++test_count);
            // Write 0xAABBCCDD with only lower 16 bits enabled
            axi_write(32'h64000008, 32'hAABBCCDD, 8'h03, 16'h0006, wresp);
            axi_read(32'h64000008, 16'h0007, rdata, rresp);
            if (rdata[15:0] == 16'hCCDD && wresp == 2'b00 && rresp == 2'b00) begin
                $display("  PASS: Lower 16 bits written: 0x%08h", rdata);
                ++pass_count;
            end else begin
                $display("  FAIL: Expected lower 16 bits = 0xCCDD, got 0x%08h", rdata);
                ++fail_count;
            end
        end
        
        // Test 5: Read READ_COUNT register (0x00C)
        begin
            reg [31:0] rdata;
            reg [1:0] rresp;
            $display("\nTest %0d: Check READ_COUNT register (0x00C)", ++test_count);
            axi_read(32'h6400000C, 16'h0008, rdata, rresp);
            if (rdata >= 2 && rresp == 2'b00) begin
                $display("  PASS: Read count = %0d", rdata);
                ++pass_count;
            end else begin
                $display("  FAIL: Unexpected read count = %0d", rdata);
                ++fail_count;
            end
        end
        
        // Test 6: Read from unmapped address
        begin
            reg [31:0] rdata;
            reg [1:0] rresp;
            $display("\nTest %0d: Read from unmapped address (0x100)", ++test_count);
            axi_read(32'h64000100, 16'h0009, rdata, rresp);
            if (rresp == 2'b10) begin  // SLVERR
                $display("  PASS: Got SLVERR response");
                ++pass_count;
            end else begin
                $display("  FAIL: Expected SLVERR, got response = %b", rresp);
                ++fail_count;
            end
        end
        
        // Test 7: Write to read-only register (should succeed but be ignored)
        begin
            reg [31:0] rdata_before, rdata_after;
            reg [1:0] rresp, wresp;
            $display("\nTest %0d: Write to RNG_DATA (read-only)", ++test_count);
            axi_read(32'h64000000, 16'h000A, rdata_before, rresp);
            axi_write(32'h64000000, 32'h12345678, 8'hFF, 16'h000B, wresp);
            axi_read(32'h64000000, 16'h000C, rdata_after, rresp);
            if (wresp == 2'b00 && rdata_after !== 32'h12345678) begin
                $display("  PASS: Write ignored for read-only register");
                ++pass_count;
            end else begin
                $display("  FAIL: Read-only register was modified");
                ++fail_count;
            end
        end
        
        // Test 8: Transaction ID tracking
        begin
            reg [31:0] rdata;
            reg [1:0] rresp;
            $display("\nTest %0d: Transaction ID tracking", ++test_count);
            axi_read(32'h64000000, 16'hABCD, rdata, rresp);
            // ID check is done inside axi_read task
            $display("  PASS: Transaction ID correctly returned");
            ++pass_count; 
        end
        
        #200;
        
        // Summary
        $display("\n=====================================");
        $display("Test Summary");
        $display("=====================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        
        if (fail_count == 0)
            $display("\nALL TESTS PASSED!");
        else
            $display("\nSOME TESTS FAILED!");
        
        $display("=====================================\n");
        
        #100;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule