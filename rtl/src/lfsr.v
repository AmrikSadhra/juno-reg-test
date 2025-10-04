`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.10.2025 09:26:57
// Design Name: 
// Module Name: lfsr
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


module lfsr #(
    parameter DATA_WIDTH = 32
)(
    input ACLK,
    input ARESETn,
    input read_enable,
    output [31:0] random_data
);

    reg[DATA_WIDTH-1:0] lfsr_reg;

    // 32 bit LFSR with taps at positions 32, 22, 2, 1 (maximal length)
    wire feedback = lfsr_reg[31] ^ lfsr_reg[21] ^ lfsr_reg[1] ^ lfsr_reg[0];

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn)
            lfsr_reg <= 32'hACE1;
        else
            lfsr_reg <= {lfsr_reg[30:0], feedback};
    end

    assign random_data = lfsr_reg;

endmodule


