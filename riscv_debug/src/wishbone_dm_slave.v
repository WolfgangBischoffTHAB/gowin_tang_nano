// the JTAG client has performed a abstract command via writing to DM.command 
// The abstract command is a "read from memory" (not a write!)
// This is NOT a read from data0!!!
//`define DEBUG_OUTPUT_MEM_READ_TRIGGERED 1
`undef DEBUG_OUTPUT_MEM_READ_TRIGGERED

// DEBUG Register Data 0 written to
//`define DEBUG_OUTPUT_DATA0_REG_WRITE 1
`undef DEBUG_OUTPUT_DATA0_REG_WRITE

// DEBUG Register Data 1 written to
//`define DEBUG_OUTPUT_DATA1_REG_WRITE 1
`undef DEBUG_OUTPUT_DATA1_REG_WRITE

// DEBUG Register Data 0 is read
//`define DEBUG_OUTPUT_DATA0_REG_READ 1
`undef DEBUG_OUTPUT_DATA0_REG_READ

// DEBUG Register Data 1 is read
//`define DEBUG_OUTPUT_DATA1_REG_READ 1
`undef DEBUG_OUTPUT_DATA1_REG_READ

//`define DEBUG_OUTPUT_WISHBONE_READ_DONE 1
`undef DEBUG_OUTPUT_WISHBONE_READ_DONE

//`define DEBUG_OUTPUT_ACK 1
`undef DEBUG_OUTPUT_ACK

//`define DEBUG_OUTPUT_MEMORY_ACCESS_TIMER_EXPIRED 1
`undef DEBUG_OUTPUT_MEMORY_ACCESS_TIMER_EXPIRED

`define DEBUG_OUTPUT_DM_CONTROL_WRITTEN 1
//`undef DEBUG_OUTPUT_DM_CONTROL_WRITTEN

// DM (RISCV DebugSpec, DM)
//
module wishbone_dm_slave 
#(
    parameter DATA_NUM = 16
)
(

    // input
    input wire clk_i, // clock input
	input wire rst_i, // asynchronous reset input, low active

    // input (slaves)
    input wire [31:0] addr_i, // address within a wishbone slave
    input wire we_i, // write enable, 1 = write, 0 = read
    input wire [63:0] data_i, // data for the slave to consume
    input wire cyc_i, // master starts and terminates cycle
    input wire stb_i, // master starts and terminates strobes

    // input - custom input goes here ...
    input wire [31:0] instr_i,

    output wire we_imem_i,
    output wire [31:0] write_data_imem_i,

    // output (slaves)
    output wire [63:0] data_o, // data that the slave produces
    output wire ack_o,  // - ack is deasserted until the master starts a cycle/strobe
                        // - ack has to be asserted when data is provided and as long as 
                        //   the master asserts cyc_i and stb_i
                        // - ack goes low once the master stops the cycle/strobe

    // output - custom output goes here ...
    output wire [5:0] led_port_o,
    output wire [31:0] pc_o,
    output wire clock_signal_selector_o,

    // printf - needs to be enabled in top module by assigning values to these two ports
    // does not work because this state machine is not clocked and this causes a cycle in the tree
    output reg [DATA_NUM * 8 - 1:0] send_data, // printf debugging over UART
    output reg printf // printf debugging over UART

);

localparam ZERO_VALUE = 0;

reg clock_signal_selector_reg = 0;
assign clock_signal_selector_o = clock_signal_selector_reg;

//
// DM (RISCV DebugSpec, DM)
//
// All the DM's registers are listed table 3.8 on page 20
//

// dm.data0 (0x04) register, page 30
localparam ADDRESS_DM_DATA0_REGISTER = 32'h00000004;
reg [63:0] data0_reg = ZERO_VALUE;

// dm.data1 (0x05) register, page 30
localparam ADDRESS_DM_DATA1_REGISTER = 32'h00000005;
reg [63:0] data1_reg = ZERO_VALUE;

// dm.control (0x10) register, page 22
localparam ADDRESS_DM_CONTROL_REGISTER = 32'h00000010;
reg [63:0] control_reg = ZERO_VALUE;

// dm.command (0x17) register, page 28
localparam ADDRESS_DM_COMMAND_REGISTER = 32'h00000017;
reg [63:0] command_reg = ZERO_VALUE;

reg [31:0] pc_o_reg;
assign pc_o = pc_o_reg;

reg we_imem_i_reg = 0;
assign we_imem_i = we_imem_i_reg;

reg [31:0] write_data_imem_i_reg = 0;
assign write_data_imem_i = write_data_imem_i_reg;

localparam HALTREQ = 31;
localparam RESUMEREQ = 30;
localparam HARTRESET = 29;

reg [31:0] counter_reg = 0;

//
// DualSource Registers
//

// data0_source_write_reg is used to fill data0_reg with data from
// the abstract command "write_register" instead of filling data0_reg with a value from 
// the abstract command "read_memory" (e.g. by reading a value from a RAM address) 
// If you want to execute an abstract command "read_memory", you have to 
// toggle 'data0_source_mem_access_data'
reg data0_source_write_reg_old = 0;
reg data0_source_write_reg = 0;

// data0_source_mem_access_data is used to fill data0_reg with data from
// the internal system (e.g. by reading a value from a RAM address using abstract command "read_memory") 
// instead of filling data0_reg with a value from an abstract command "write_register".
// If you want to execute an abstract command "write_register", you have to 
// toggle 'data0_source_write_reg'
reg data0_source_mem_access_data_old = 0;
reg data0_source_mem_access_data = 0;

reg instruction_memory_read_done_reg_old = 0;
reg instruction_memory_read_done_reg = 0;

reg [7:0] abstr_cmdtype_reg;
reg       abstr_aamvirtual_reg;
reg [2:0] abstr_aamsize_reg;
reg       abstr_aampostincrement_reg;
reg       abstr_write_reg;
reg [1:0] abstr_target_specific_reg;

// fields of the dm.command register
reg haltreq                 = 0; // Writing 0 clears the halt request bit for all currently selected harts ...
reg resumereq               = 0; // Writing 1 causes the currently selected harts to resume once ...
reg hartreset               = 0; //
reg ackhavereset            = 0; //
reg hasel                   = 0; //
reg [9:0] hartsello         = 0; //
reg [9:0] hartselhi         = 0; //
reg [1:0] setresethaltreq   = 0; //
reg clrresethaltreq         = 0; //
reg ndmreset                = 0; // This bit controls the reset signal from the DM to the rest of the system.
reg dmactive                = 0; //

// this block is here because the register 'data0_reg' has to be updated by two sources:
// 1. the abstract command write register command 
// 2. from a abstract command read memory command
always @(posedge clk_i)
begin

    // if reset is asserted, 
    if (rst_i) 
    begin
        // add line for new register here
        data0_reg = ZERO_VALUE;

        we_imem_i_reg = 0;
    end    
    else 
    begin

        // This case is for the abstract command to write into a register
        // data0_reg is assigned the ... register
        if (data0_source_write_reg_old != data0_source_write_reg)
        begin
            data0_source_write_reg_old = data0_source_write_reg;

            // update data0_reg
            data0_reg = data_i[31:0];

`ifdef DEBUG_OUTPUT_DATA0_REG_WRITE
            // DEBUG - data0 update from mem_access triggered
            send_data = { 8'h4A };
            printf = ~printf;
`endif
        end

        // data0_reg is assigned the wishbone transaction result
        if (data0_source_mem_access_data_old != data0_source_mem_access_data)
        begin
            data0_source_mem_access_data_old = data0_source_mem_access_data;

            // the JTAG client has performed an abstract command via writing to DM.command
            // This is NOT a read from data0!!!
            
            // The abstract command might be a "read from memory" (not a write!)
            // The abstract command might be a "write to memory" (not a read!)
            // TODO add logic to identify and handle commands

            abstr_cmdtype_reg = data_i[31:24]; // 0x02 is read from memory
            abstr_aamvirtual_reg = data_i[23]; // aamvirtual - 0 == no virtual memory translation
            abstr_aamsize_reg = data_i[22:20]; // aamsize == 2dec = 32 bit data transfer
            abstr_aampostincrement_reg = data_i[19]; // aampostincrement - 0 = no postincrement
            abstr_write_reg = data_i[16]; // write - (0 == write, 1 == read)
            abstr_target_specific_reg = data_i[15:14];

            case (abstr_cmdtype_reg)

                8'h02:
                begin

                    case (abstr_write_reg)

                        8'h00: // write
                        begin
`ifdef DEBUG_OUTPUT_MEM_READ_TRIGGERED
                            // DEBUG - read memory abstract command
                            send_data = { 8'h4C };
                            printf = ~printf;
`endif
                    
                            // data0 contains the data to write
                            // data1 contains the address to write the data to
                            pc_o_reg = data1_reg[31:0];

                            // write enable to imem
                            we_imem_i_reg = 1;

                            write_data_imem_i_reg = data0_reg[31:0];
                        end

                        8'h01: // read
                        begin
`ifdef DEBUG_OUTPUT_MEM_READ_TRIGGERED
                            // DEBUG - read memory abstract command
                            send_data = { 8'h4D };
                            printf = ~printf;
`endif
                            //
                            // interface the instruction memory at the address stored in PC.
                            // Read the memory value from instr_i
                            //

                            // to imem: perform read enable (instead of write enable)
                            we_imem_i_reg = 0;

                            // memory address is expected in data1
                            pc_o_reg = data1_reg[31:0];

                        end
                        
                    endcase

                end

            endcase

`ifdef DEBUG_OUTPUT_DATA0_REG_WRITE
            // DEBUG - data0 update from mem_access triggered
            send_data = { 8'h4B };
            printf = ~printf;
`endif

        end

        if (instruction_memory_read_done_reg_old != instruction_memory_read_done_reg)
        begin
            instruction_memory_read_done_reg_old = instruction_memory_read_done_reg;

            // take the data from memory and put it into data0_reg once the memory access had time to finish
            data0_reg = instr_i;
        end

    end
end

//
// WISHBONE
// 

reg transaction_done = 0; // only perform a reaction to a write operation once

reg [5:0] led_reg = ~6'h00;
assign led_port_o = ~led_reg;

reg [63:0] data_o_reg = ZERO_VALUE;
assign data_o = data_o_reg;

reg ack_o_reg;
assign ack_o = ack_o_reg;

// wishbone slave state machine
localparam IDLE = 0;
localparam READ = 1;
localparam WRITE = 2;

// current and next_state
reg [1:0] cur_state = IDLE;
reg [1:0] next_state;

// next state logic + write operation
always @(posedge clk_i) 
begin
    
    // if reset is asserted, 
    if (rst_i) 
    begin
        // go back to IDLE state
        cur_state = IDLE;

        // STEP 3 - add line for new register here
        //data0_reg = ZERO_VALUE;
        data1_reg = ZERO_VALUE;
        control_reg = ZERO_VALUE;
        command_reg = ZERO_VALUE; 
    end    
    else 
    begin
        // else transition to the next state
        cur_state = next_state;

        // store the input data into a register here instead of inside the state machine as
        // the state machine is not clocked and hence the assignment to a 
        // register would cause a latch
        if ((cur_state == WRITE) && (cyc_i == 1 && stb_i == 1))
        begin

            // STEP 4 - add line for new register here
            case (addr_i)

                // write dm.data0 (0x04)
                ADDRESS_DM_DATA0_REGISTER:
                begin
                    // data0_reg is indirectly written to (using the toggle bit) because
                    // data0_reg can also be update by another abstract command (read_memory!)
                    // so data0_reg has two sources
                    data0_source_write_reg = ~data0_source_write_reg;
                end

                // write dm.data1 (0x05)
                ADDRESS_DM_DATA1_REGISTER:
                begin
                    data1_reg = data_i; // store the written value into the data1 register of this DM

`ifdef DEBUG_OUTPUT_DATA1_REG_WRITE
                    // DEBUG - data1 update from mem_access triggered
                    send_data = { 8'h4F };
                    printf = ~printf;
`endif
                end

                // write dm.dmcontrol (0x10)
                ADDRESS_DM_CONTROL_REGISTER:
                begin
                    control_reg = data_i; // store the written value into the control register of this DM
                end

                // write dm.dmcontrol (0x17)
                ADDRESS_DM_COMMAND_REGISTER:
                begin
                    command_reg = data_i; // store the written value into the command register of this DM
                end

                default:
                begin                    
                end

            endcase

        end

    end

end

// combinational always block for next state logic of the wishbone state machine
always @(posedge clk_i)
begin

    case (cur_state)

        IDLE:
        begin
            // reset
            data_o_reg = ZERO_VALUE;
            ack_o_reg = 0;
            transaction_done = 0; // reset because no write operation has completed yet

            // master starts a transaction
            if (cyc_i == 1 && stb_i == 1)
            begin
                if (we_i == 1)
                begin
                    next_state = WRITE;
                end
                else
                begin
                    next_state = READ;
                end
            end
            else
            begin
                next_state = IDLE;
            end
        end

        READ:
        begin
            // The slave will keep ACK_I asserted until the master negates 
            // [STB_O] and [CYC_O] to indicate the end of the cycle.
            if (cyc_i == 1 || stb_i == 1)
            begin
                
                // STEP 5 - add line for new register here
                case (addr_i)

                    // dm.data0 (0x04)
                    ADDRESS_DM_DATA0_REGISTER:
                    begin
                        data_o_reg = data0_reg; // present the read data

`ifdef DEBUG_OUTPUT_DATA0_REG_READ
                        // DEBUG - data0 update from mem_access triggered
                        //send_data = { 8'h30 };
                        send_data = data0_reg[7:0];
                        printf = ~printf;
`endif
                    end

                    // dm.data1 (0x05)
                    ADDRESS_DM_DATA1_REGISTER:
                    begin
                        data_o_reg = data1_reg; // present the read data

`ifdef DEBUG_OUTPUT_DATA1_REG_READ
                        // DEBUG - data1 update from mem_access triggered
                        send_data = { 8'h31 };
                        printf = ~printf;
`endif
                    end

                    // dm.control (0x10)
                    ADDRESS_DM_CONTROL_REGISTER:
                    begin
                        data_o_reg = control_reg; // present the read data
                    end

                    // dm.command (0x17)
                    ADDRESS_DM_COMMAND_REGISTER:
                    begin
                        data_o_reg = command_reg; // present the read data
                    end

                    default:
                    begin
                        data_o_reg = ZERO_VALUE;
                    end

                endcase

                // acknowledge read
                ack_o_reg = 1;

                next_state = cur_state;
            end
            else
            begin
                data_o_reg = ZERO_VALUE; // output a dummy value
                ack_o_reg = 0;

                next_state = IDLE;
            end
        end

        WRITE:
        begin

            // The slave will keep ACK_I asserted until the master negates 
            // [STB_O] and [CYC_O] to indicate the end of the cycle.
            //
            // HINT: the actual write is performed in the next state logic as it is clocked
            if (cyc_i == 1 || stb_i == 1)
            begin

                // STEP 6 - add line for new register here
                case (addr_i)

                    // 0x04
                    ADDRESS_DM_DATA0_REGISTER:
                    begin
                        // data is stored inside the next state logic
                        data_o_reg = data0_reg; // present the read data (this is basically a read operation!)
                    end

                    // 0x05
                    ADDRESS_DM_DATA1_REGISTER:
                    begin
                        // data is stored inside the next state logic
                        data_o_reg = data1_reg; // present the read data (this is basically a read operation!)
                    end

                    // 0x10
                    ADDRESS_DM_CONTROL_REGISTER:
                    begin
                        // data is stored inside the next state logic
                        data_o_reg = control_reg; // present the read data (this is basically a read operation!)
                    end

                    // 0x17
                    ADDRESS_DM_COMMAND_REGISTER:
                    begin
                        // data is stored inside the next state logic
                        data_o_reg = command_reg; // present the read data (this is basically a read operation!)
                    end

                    default:
                    begin
                        data_o_reg = ZERO_VALUE;
                    end

                endcase                

                // only if there has not been a reaction to the latest finished write transaction, 
                // perform a reaction
                if (transaction_done == 0)
                begin
                    transaction_done = 1; // buffer the reaction in order to not repeat it again

                    //
                    // This block is only executed once
                    //

                    // STEP 7 - add line for new register here
                    case (addr_i)

                        // write dm.data0 (0x04)
                        ADDRESS_DM_DATA0_REGISTER:
                        begin
                        end

                        // write dm.data1 (0x05)
                        ADDRESS_DM_DATA1_REGISTER:
                        begin
                        end

                        // write dm.control (0x10)
                        ADDRESS_DM_CONTROL_REGISTER:
                        begin
                            // The control register is written to.
                            // This can be used to perform a ndmreset for example to reset all harts
//`ifdef DEBUG_OUTPUT_DM_CONTROL_WRITTEN
//                            // DEBUG
//                            send_data = { 8'h77 };
//                            printf = ~printf;
//`endif

                            haltreq         = data_i[31];       // Writing 0 clears the halt request bit for all currently selected harts ...
                            resumereq       = data_i[30];       // Writing 1 causes the currently selected harts to resume once ...
                            hartreset       = data_i[29];       //
                            ackhavereset    = data_i[28];       //
                            hasel           = data_i[26];       //
                            hartsello       = data_i[25:16];    //
                            hartselhi       = data_i[15:6];     //
                            setresethaltreq = data_i[3];        //
                            clrresethaltreq = data_i[2];        //
                            ndmreset        = data_i[1];        // This bit controls the reset signal from the DM to the rest of the system.
                            dmactive        = data_i[0];        //

                            if (haltreq == 1'b1)
                            begin
`ifdef DEBUG_OUTPUT_DM_CONTROL_WRITTEN
                            // DEBUG
                            send_data = { 8'h70 };
                            printf = ~printf;
`endif
                            clock_signal_selector_reg = 1'b1;
                            end
/*                            else
                            begin
`ifdef DEBUG_OUTPUT_DM_CONTROL_WRITTEN
                            // DEBUG
                            send_data = { 8'h71 };
                            printf = ~printf;
`endif
                            end*/

                            if (resumereq == 1'b1)
                            begin
`ifdef DEBUG_OUTPUT_DM_CONTROL_WRITTEN
                            // DEBUG
                            send_data = { 8'h72 };
                            printf = ~printf;
`endif
                            clock_signal_selector_reg = 1'b0;
                            end
/*                            else
                            begin
`ifdef DEBUG_OUTPUT_DM_CONTROL_WRITTEN
                            // DEBUG
                            send_data = { 8'h73 };
                            printf = ~printf;
`endif
                            end*/

                            if (ndmreset == 1'b1)
                            begin
`ifdef DEBUG_OUTPUT_DM_CONTROL_WRITTEN
                            // DEBUG
                            send_data = { 8'h74 };
                            printf = ~printf;
`endif
                            end
/*                            else
                            begin
`ifdef DEBUG_OUTPUT_DM_CONTROL_WRITTEN
                            // DEBUG
                            send_data = { 8'h75 };
                            printf = ~printf;
`endif
                            end*/

                        end

                        // write dm.command (0x17)
                        ADDRESS_DM_COMMAND_REGISTER:
                        begin
                            // execute the abstract command! (e.g. access memory)

                            // wait for imem access
                            counter_reg = 0;

                            // data0_source_mem_access_data is used to fill data0_reg with data from
                            // the internal system (e.g. by reading a value from a RAM address) instead
                            // of filling data0_reg with a value from an abstract command "write_register".
                            //
                            // If you want to execute an abstract command "write_register", you have to 
                            // toggle 'data0_source_write_reg'
                            data0_source_mem_access_data = ~data0_source_mem_access_data;
                        end

                        default:
                        begin                    
                        end

                    endcase
                end
                
                if (counter_reg == 32'h017D7840) // 25 mio = 1 sec
                begin
`ifdef DEBUG_OUTPUT_MEMORY_ACCESS_TIMER_EXPIRED
                        // DEBUG
                        send_data = { 8'h99 };
                        printf = ~printf;
`endif

                    // reset counter variable
                    counter_reg = 0;

                    // read enable imem
                    //we_imem_i_reg = 0;

                    // update data0_reg with dummy value for now
                    instruction_memory_read_done_reg = ~instruction_memory_read_done_reg;

                    // acknowledge write
                    ack_o_reg = 1;
                end
                else
                begin
                    counter_reg = counter_reg + 1;
                end

                next_state = cur_state;
            end
            else
            begin
                data_o_reg = ZERO_VALUE;
                ack_o_reg = 0;
                next_state = IDLE;
            end
        end

        default:
        begin
            data_o_reg = ~32'b00;
            ack_o_reg = 0;

            next_state = cur_state;
        end

    endcase

end

endmodule