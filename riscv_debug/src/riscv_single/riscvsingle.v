`define DEBUG_OUTPUT_PC 1
//`undef DEBUG_OUTPUT_PC

module riscvsingle #(
    parameter DATA_NUM = 16
)(

    input wire clk, 
    input wire reset_n,
    output wire [31:0] PC,
    input wire [31:0] Instr,
    output wire MemWrite,
    output wire [31:0] ALUResult, 
    output wire [31:0] WriteData,
    input wire [31:0] ReadData,
    output wire [2:0] ALUControl,
    output wire led,

    // printf - needs to be enabled in top module by assigning values to these two ports
    // does not work because this state machine is not clocked and this causes a cycle in the tree
    output reg [DATA_NUM * 8 - 1:0] send_data, // printf debugging over UART
    output reg printf // printf debugging over UART

);

    wire ALUSrc, RegWrite, Jump, Zero;
    wire [1:0] ResultSrc, ImmSrc;
    wire PCSrc;

    controller c(
        Instr[6:0], 
        Instr[14:12], 
        Instr[30], 
        Zero, 
        ResultSrc, 
        MemWrite, 
        PCSrc, 
        ALUSrc, 
        RegWrite, 
        Jump, 
        ImmSrc, 
        ALUControl
    );

    datapath dp(
        clk, 
        reset_n, 
        ResultSrc, 
        PCSrc, 
        ALUSrc, 
        RegWrite, 
        ImmSrc, 
        ALUControl, 
        Zero, 
        PC, 
        Instr, 
        ALUResult, 
        WriteData,
        ReadData
    );

    //
    // DEBUG: blink a LED
    //

    reg led_reg;
    assign led = led_reg;

    always @(posedge clk)
    begin
        led_reg = ~led_reg;
    end

    //
    // DEBUG print PC
    //

    always @(posedge clk)
    begin
`ifdef DEBUG_OUTPUT_PC
        // DEBUG
        send_data = { PC[7:0] };
        printf = ~printf;
`endif
    end

endmodule