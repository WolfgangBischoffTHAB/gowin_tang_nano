module imem(
    
    // input
    input wire          clk,
    input wire          sys_rst_n,
    input wire          we, // write enable
    input wire [31:0]   a, // address    
    input wire [31:0]   write_data, // data to write to the address

    // output
    output wire [31:0] rd

);

    reg [31:0] rd_reg = 0;
    assign rd = rd_reg;    

    // 64 locations, each storing 32 bits
    reg [31:0] RAM[63:0]; 

    //initial
    //   $readmemh("progmem.txt", RAM);

/*
    __main:
    loop_start:
        addi x5, x0, 0x0
        addi x6, x0, 0x0
        lui x7, 0
        addi x7, x7, 2

    busy_loop_start:	
        beq x5, x7, 0xC             # if (x5 == x7) jump to loop_end (pc relative jump of +12 bytes)
        addi x5, x5, 1
        jal x0, busy_loop_start     # jal loop head (pc relative jump back -8 bytes)

    busy_loop_end:
        lw x6, 52(x0)               # load data from mem-address 52 into x6
        xori x6, x6, 1              # toggle the value stored inside x6
        sw x6, 52(x0)               # write data from x6 into mem-address 52

        jal x0, loop_start

    00 - 00000293
    04 - 00000313
    08 - 000003b7
    0C - 00238393
    10 - 00728663
    14 - 00128293
    18 - ff9ff06f
    1C - 03402303
    20 - 00134313
    24 - 02602a23
    28 - fd9ff06f
*/

    //always @(negedge sys_rst_n)
    always @(posedge clk)
    begin

        if (sys_rst_n == 0)
            begin

                RAM[0] = 32'h00000293;
                RAM[1] = 32'h00000313;
                RAM[2] = 32'h000003b7;
                RAM[3] = 32'h00238393;
                RAM[4] = 32'h00728663;
                RAM[5] = 32'h00128293;
                RAM[6] = 32'hff9ff06f;
                RAM[7] = 32'h03402303;
                RAM[8] = 32'h00134313;
                RAM[9] = 32'h02602a23;

                RAM[10] = 32'hfd9ff06f;
                RAM[11] = 32'h00000000;
                RAM[12] = 32'h00000000;
                RAM[13] = 32'h00000000;
                RAM[14] = 32'h00000000;
                RAM[15] = 32'h00000000;
                RAM[16] = 32'h00000000;
                RAM[17] = 32'h00000000;
                RAM[18] = 32'h00000000;
                RAM[19] = 32'h00000000;

                RAM[20] = 32'h00000000;
                RAM[21] = 32'h00000000;
                RAM[22] = 32'h00000000;
                RAM[23] = 32'h00000000;
                RAM[24] = 32'h00000000;
                RAM[25] = 32'h00000000;
                RAM[26] = 32'h00000000;
                RAM[27] = 32'h00000000;
                RAM[28] = 32'h00000000;
                RAM[29] = 32'h00000000;

                RAM[30] = 32'h00000000;
                RAM[31] = 32'h00000000;
                RAM[32] = 32'h00000000;
                RAM[33] = 32'h00000000;
                RAM[34] = 32'h00000000;
                RAM[35] = 32'h00000000;
                RAM[36] = 32'h00000000;
                RAM[37] = 32'h00000000;
                RAM[38] = 32'h00000000;
                RAM[39] = 32'h00000000;

                RAM[40] = 32'h00000000;
                RAM[41] = 32'h00000000;
                RAM[42] = 32'h00000000;
                RAM[43] = 32'h00000000;
                RAM[44] = 32'h00000000;
                RAM[45] = 32'h00000000;
                RAM[46] = 32'h00000000;
                RAM[47] = 32'h00000000;
                RAM[48] = 32'h00000000;
                RAM[49] = 32'h00000000;

                RAM[50] = 32'h00000000;
                RAM[51] = 32'h00000000;
                RAM[52] = 32'h00000000;
                RAM[53] = 32'h00000000;
                RAM[54] = 32'h00000000;
                RAM[55] = 32'h00000000;
                RAM[56] = 32'h00000000;
                RAM[57] = 32'h00000000;
                RAM[58] = 32'h00000000;
                RAM[59] = 32'h00000000;

                RAM[60] = 32'h00000000;
                RAM[61] = 32'h00000000;
                RAM[62] = 32'h00000000;
                RAM[63] = 32'h00000000;
            
            end
        else
            begin
                if (we == 1)
                    begin
                        RAM[a[31:2]] = write_data;
                    end
                else
                    begin
                        rd_reg = RAM[a[31:2]]; // word aligned
                    end
            end
    
    end

endmodule