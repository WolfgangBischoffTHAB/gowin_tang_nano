`define DEBUG_OUTPUT_DM_WB_SLAVE 1
//`undef DEBUG_OUTPUT_DM_WB_SLAVE

//`define DEBUG_OUTPUT_WB_MASTER 1
`undef DEBUG_OUTPUT_WB_MASTER

//`define DEBUG_OUTPUT_JTAG_TAP 1
`undef DEBUG_OUTPUT_JTAG_TAP

//`define DEBUG_OUTPUT_RISCV_CPU 1
`undef DEBUG_OUTPUT_RISCV_CPU

// the state machine that runs the demo application has three states: IDLE, SEND and WAIT
//
// IDLE is entered on reset. IDLE immediately transitions to SEND.
// IDLE does not perform any action.
//
// SEND is entered after IDLE and when the wait period is over.
// During SEND a string of DATA_NUM characters is transmitted, one
// character per clock tick. Once all characters are transmitted,
// the transition to WAIT takes place because the demo wants to 
// wait around for some time before sending DATA_NUM characters again.
//
// In WAIT, the system remains still whithout sending data for one
// second. WAIT is the only state, where the system checks for incoming data.
// If a byte is received, that exact byte is immediately sent out over the tx line.
// 

module top(

    // input
    input wire sys_clk,         // clk input
    input wire sys_rst_n,       // reset input button  (active low)
	input wire uart_rx,         // UART RX
//    input wire btn1_n,          // push button 1 (active low)
    input wire jtag_clk,
    input wire jtag_tdi_i,
    input wire jtag_tms,

    // output
    output wire [5:0] led,      // 6 LEDS pin
	output wire uart_tx,        // UART TX
    output wire jtag_tdo

);

assign led[0] = 0;
assign led[1] = 0;
assign led[2] = 0;
//assign led[3] = 0; // LED 3 - connected to dmem
//assign led[4] = 0; // LED 4 - connected to the RISCV CPU
//assign led[5] = 0; // LED 5 - On MemWrite in top level module

/*
assign led[0] = ~jtag_tdi_i;
assign led[1] = jtag_tdi_i;
assign led[2] = ~jtag_tdi_i;
assign led[3] = jtag_tdi_i;
assign led[4] = ~jtag_tdi_i;
assign led[5] = jtag_tdi_i;
*/
/*
assign led[0] = ~jtag_clk;
assign led[1] = jtag_clk;
assign led[2] = ~jtag_clk;
assign led[3] = jtag_clk;
assign led[4] = ~jtag_clk;
assign led[5] = jtag_clk;
*/

wire sys_rst_n_debounced;

// Instantiate Debounce Module for the reset button
Debounce_Switch debounce_sys_rst_n
(
    .i_Clk(sys_clk), 
    .i_Switch(sys_rst_n),
    .o_Switch(sys_rst_n_debounced)
);

/**/
wire debounced_jtag_clk_wire;

// Instantiate Debounce Module for the debounce JTAG
Debounce_Switch 
#(
    //.DEBOUNCE_LIMIT(250000)
    .DEBOUNCE_LIMIT(250000) // 250000 = 10 ms at 25 MHz
)
debounce_jtag_clk (
    .i_Clk(sys_clk), 
    .i_Switch(jtag_clk),
    .o_Switch(debounced_jtag_clk_wire)
);


/*
//
// user button demo application
//

// http://nandland.com/project-4-debounce-a-switch/

reg  r_Switch_1 = 1'b0;
wire w_Switch_1;

// Instantiate Debounce Module
Debounce_Switch debounce_Inst
(
    .i_Clk(sys_clk), 
    .i_Switch(btn1_n),
    .o_Switch(w_Switch_1)
);
*/


//
// DEFAULT
//
//reg [5:0] led_reg = 6'b111111;
//assign led = led_reg;

//
// printf
//

parameter DATA_NUM = 1;
wire [DATA_NUM * 8 - 1:0] send_data; // bits to send
// DEBUG control the uart tx
//reg printf = 1'b0;
wire printf;

//
// Drive clock_out_reg from [sys_clk] => [clock_divider] => clock_out_reg
//

// divide clock into the slow clock
// Mhz. The Tang Nano 9K has a 27 Mhz clock source on board

wire slow_clock_out;
reg slow_clock_out_reg;
assign slow_clock_out = slow_clock_out_reg;

reg [31:0] slow_counter = 32'd0;
parameter SLOW_DIVISOR = 32'd27000000;
always @(posedge sys_clk)
begin
    slow_counter <= slow_counter + 32'd1;
    if (slow_counter >= (SLOW_DIVISOR - 1))
    begin
        slow_counter <= 32'd0;
    end
    slow_clock_out_reg <= (slow_counter < (SLOW_DIVISOR / 2)) ? 1'b1 : 1'b0;
end

// divide clock into the mid clock
// Mhz. The Tang Nano 9K has a 27 Mhz clock source on board

wire mid_clock_out;
reg mid_clock_out_reg;
assign mid_clock_out = mid_clock_out_reg;

reg [31:0] mid_counter = 32'd0;
parameter MID_DIVISOR = 32'd13500000;
always @(posedge sys_clk)
begin
    mid_counter <= mid_counter + 32'd1;
    if (mid_counter >= (MID_DIVISOR - 1))
    begin
        mid_counter <= 32'd0;
    end
    mid_clock_out_reg <= (mid_counter < (MID_DIVISOR / 2)) ? 1'b1 : 1'b0;
end

// clock that is off

wire off_clock_out = 1'b0;

//
// RISCV CPU
//

wire we_imem;
wire [31:0] write_data_imem;
wire [2:0] ALUControl;
wire [31:0] PC; // goes out ti imem as an address wire
wire [31:0] processor_PC;
wire [31:0] dm_PC;
// TODO: hook up the hardcoded select (param 3) to the DebugSpec DM slave for abstract write commands to work
mux2 #(32) PC_mux(dm_PC, processor_PC, 1'b1, PC); // [input 0][input 1][selector (0 or 1)][output]
wire [31:0] Instr;
//reg [31:0] Instr_reg;
//assign Instr = Instr_reg;
wire [31:0] ReadData;
wire [31:0] WriteData;
wire [31:0] DataAdr;
wire MemWrite;

// DEBUG: store the current clock signal selector
wire clock_signal_selector;
reg clock_signal_selector_reg = 0;
always @(posedge sys_clk)
begin
    clock_signal_selector_reg = clock_signal_selector;
end

wire clock;
mux2 #(1) clock_mux(slow_clock_out, off_clock_out, clock_signal_selector_reg, clock); // [input 0][input 1][selector (0 or 1)][output]

// instantiate processor
riscvsingle #(.DATA_NUM(DATA_NUM)) rvsingle(

    //.clk(slow_clock_out), // input, slow clock
    .clk(clock), // Input, mid clock
    .reset_n(sys_rst_n_debounced), 
    .PC(processor_PC), // output
    .Instr(Instr), 
    .MemWrite(MemWrite), // output
    .ALUResult(DataAdr), 
    .WriteData(WriteData), 
    .ReadData(ReadData),
    .ALUControl(ALUControl),
    .led(led[4]), // led 4 - blinks LED 4 every clk edge

`ifdef DEBUG_OUTPUT_RISCV_CPU
    // printf - enabled
    .send_data(send_data),
    .printf(printf)    
`else
    // printf - disabled
    .send_data(),
    .printf()
`endif

);

reg led_5_reg = 0;
assign led[5] = led_5_reg;

always @(posedge MemWrite)
begin
    led_5_reg = ~led_5_reg;
end

// instruction memory
imem imem(

    // input
    .clk(sys_clk), // fast clock
    .sys_rst_n(sys_rst_n_debounced),
    .we(we_imem),
    .a(PC),    
    .write_data(write_data_imem),

    // output
    .rd(Instr)
);

// data memory
dmem dmem(

    // input
    .clk(sys_clk), // fast clock
    .reset_n(sys_rst_n_debounced),
    .we(MemWrite), // write enable for dmem
    .a(DataAdr),
    .wd(WriteData),

    // output
    .rd(ReadData),
    .led(led[3]) // blink the led whenever write enable is true

);






//
// wishbone master
//

wire wishbone_master_ack; // the wishbone master tells the JTAG TAP that the transaction is over
wire [63:0] last_read_value;

wire [63:0] read_data; // the wishbone slave places read data here
wire [63:0] write_data; // master places write data for the slave to consume on a write cycle here
wire dm_slave_ack; // wishbone slave ack output
wire cyc;
wire stb;
wire [31:0] addr; // addr for the master to write to / read from. Retrieved from the JTAG TAP.
wire we;

wire start_read_transaction; // output by the JTAG tap to cause the withbone master to read the slave
wire start_write_transaction; // output by the JTAG tap to cause the withbone master to write the slave
wire[63:0] wishbone_tx_data;
wire[31:0] wishbone_addr;

//reg [63:0] slave_read_result_reg;
wire [63:0] slave_read_result;

// This wishbone master is connected to the JTAG-TAP which uses it to
// execute read and write wishbone cycles. The slave to this master is the DM.
wishbone_master #(
    .DATA_NUM(DATA_NUM)
) wb_master (

    // input
    .clk_i(sys_clk),
    .rst_i(~sys_rst_n),

    // input master
    .data_i(read_data), // the wishbone slave places read data here
    .ack_i(dm_slave_ack), // the wishbone slave performs an ack here

    // input wbi custom 
    .start_read_transaction_i(start_read_transaction), // start a read cycle when 1
    .start_write_transaction_i(start_write_transaction), // start a write cycle when 1
    .transaction_addr(wishbone_addr), // wishbone addr in the slave
    .write_transaction_data_i(wishbone_tx_data), // data to write into the slave
    
    // output master
    .addr_o(addr),
    .we_o(we),
    .data_o(write_data), // output to the slave on write transactions
    .cyc_o(cyc),
    .stb_o(stb),

    // output wbi custom
    .read_transaction_data_o(slave_read_result), // data read from the slave during read cycles is returned here
    
//PROBLEM: Putting the ack from the wishbone slave directly into the JTAG TAP seems to not capture the read value!
//We need to get the output value from the slave into the master and from the master into the JTAG_TAP
    .wishbone_master_ack_o(wishbone_master_ack), // the wishbone master communicates to the JTAG_TAP that the transaction is over
    .last_read_value_o(last_read_value),

`ifdef DEBUG_OUTPUT_WB_MASTER
    // printf - enabled
    .send_data(send_data),
    .printf(printf)    
`else
    // printf - disabled
    .send_data(),
    .printf()
`endif
);

//
// wishbone slaves
//

// DM (RISCV Debug Spec)
wishbone_dm_slave #(
    .DATA_NUM(DATA_NUM)
) wb_dm_slave (

    // input
    .clk_i(sys_clk),
    .rst_i(~sys_rst_n),

    // input slave
    .addr_i(addr), // address within a wishbone slave
    .we_i(we),
    .data_i(write_data), // the master places the data to write into write_data
    .cyc_i(cyc),
    .stb_i(stb),

    // input custom
    .instr_i(Instr),

    // output instruction memory
    .we_imem_i(we_imem),
    .write_data_imem_i(write_data_imem),

    // output slave
    .data_o(read_data), // the slave returns the read data to the master from .data_o
    .ack_o(dm_slave_ack),

    // output wbi
    //.led_port_o(led), // output to the LEDs port
    .led_port_o(),
    .pc_o(dm_PC),
    .clock_signal_selector_o(clock_signal_selector),

`ifdef DEBUG_OUTPUT_DM_WB_SLAVE
    // printf - enabled
    .send_data(send_data),
    .printf(printf)
`else
    // printf - disabled
    .send_data(),
    .printf()
`endif   

);


/*
wishbone_led_slave #(
    .DATA_NUM(DATA_NUM)
) wb_led_slave (

    // input
    .clk_i(sys_clk),
    .rst_i(~sys_rst_n),

    // input slave
    .addr_i(addr), // address within a wishbone slave
    .we_i(we),
    .data_i(write_data), // the master places the data to write into write_data
    .cyc_i(cyc),
    .stb_i(stb),

    // input custom

    // output slave
    .data_o(read_data), // the TX slave does not use data_o. It does not return any usefull data.
    .ack_o(dm_slave_ack),

    // output wbi
    .led_port_o(led) // output to the LEDs port

    // printf - does not work because it causes a logical cycle, the state machine is not clocked
    //.send_data(send_data),
    //.printf(printf)

);
*/



//
// Timer - perform action every second
//

parameter BAUD_RATE = 115200; // serial baud rate, 115200 bits per second
parameter CLK_FRE_MHZ = CLK_FRE * 1000000;
parameter CYCLES_PER_BIT = CLK_FRE_MHZ / BAUD_RATE; // CLOCK TICKS per bit

/*
reg [31:0] counter;
reg [7:0] tx_counter;

always @(posedge sys_clk)
begin
    counter = counter + 1;

    if (counter == CLK_FRE_MHZ)
    begin

        counter = 32'd0;

        // perform action every second

// Enable this snippet for the wishbone RX slave
//        // start/stop a wishbone read transaction
//        start_read_transaction <= ~start_read_transaction;
//

//        // start the wishbone write transaction
//        start_write_transaction = 1;
//        tx_data = tx_data + 1;

//        // transmit data over the raw UART TX (without wishbone)
//        tx_data_valid = ~tx_data_valid;
//        tx_data = 8'h01;

    end

//    // ENABLE this for UART TX write
//    if (counter >= (CYCLES_PER_BIT * 8))
//    begin
//        // stop the wishbone write transaction
//        start_write_transaction = 0;
//    end

end
*/




//
// UART demo application
//

//
// combinational logic for UART
//



reg[7:0]                        tx_str;

wire[7:0]                       tx_data;
wire[7:0]                       tx_cnt;

wire                            tx_data_ready; // output of the tx module. Asserted when transmission has been performed
wire[7:0]                       rx_data;
//reg                             rx_data_ready = 1'b1; // receiving data is always enabled
localparam RX_DATA_READY = 1'b1;
wire                            tx_data_valid;

uart_controller 
#(
    .DATA_NUM(DATA_NUM)
) uart_controller_inst (

    // input
	.clk                        (sys_clk),
	.rst_n                      (sys_rst_n),
    .tx_str                     (tx_str),
    .printf                     (printf),
    .tx_data_ready              (tx_data_ready),
    .o_tx_data_valid            (tx_data_valid),
    .rx_data                    (rx_data),
    .rx_data_valid              (rx_data_valid),

    // output
    .o_tx_cnt                   (tx_cnt),
	.o_tx_data                  (tx_data)
    
);

parameter                        CLK_FRE  = 27; // Mhz. The Tang Nano 9K has a 27 Mhz clock source on board
parameter                        UART_FRE = 115200; // baudrate

always @(*)
begin
	tx_str <= send_data[(DATA_NUM - 1 - tx_cnt) * 8 +: 8];
end

uart_rx
#(
	.CLK_FRE(CLK_FRE),
	.BAUD_RATE(UART_FRE)
) uart_rx_inst (
    // input
	.clk                        (sys_clk),
	.rst_n                      (sys_rst_n),	
	.rx_data_ready              (RX_DATA_READY),
	.rx_pin                     (uart_rx),

    // output
    .rx_data                    (rx_data),
	.rx_data_valid              (rx_data_valid)
);

uart_tx
#(
	.CLK_FRE(CLK_FRE),
	.BAUD_RATE(UART_FRE)
) uart_tx_inst (
    // input
	.clk                        (sys_clk),
	.rst_n                      (sys_rst_n),
	.tx_data                    (tx_data),
	.tx_data_valid              (tx_data_valid),

    // output
	.tx_data_ready              (tx_data_ready),
	.tx_pin                     (uart_tx)
);



//
// JTAG example
//

/*
reg r_LED_1 = 1'b0;
wire [5:0] leds;
reg [5:0] r_led_reg = 6'b111111;

always @(leds)
begin
    r_led_reg <= leds;
end
*/

jtag_tap #(
    .DATA_NUM(DATA_NUM)
) jtag_tap_inst (

    //
    // JTAG
    //

    // input
    .clk(sys_clk),
    .rst_n(sys_rst_n),
    //.jtag_clk(jtag_clk),
    .jtag_clk(debounced_jtag_clk_wire),
    //.jtag_tdi(jtag_tdi),
    .jtag_tdi(jtag_tdi_i),
    .jtag_tms(jtag_tms),
    
    // output    
    .jtag_tdo(jtag_tdo),

    // debug output
    //.led_o(),

`ifdef DEBUG_OUTPUT_JTAG_TAP
    // printf - enabled
    .send_data(send_data),
    .printf(printf),
`else
    // printf - disabled
    .send_data(),
    .printf(),
`endif

    //
    // Wishbone
    //

    .read_transaction_data_i(slave_read_result), // the whishbone master places data read from the wishone slave here
    .transaction_ack_i(wishbone_master_ack), // wishbone transaction is over
    .last_read_value_i(last_read_value),

    // when a JTAG command for dmi (0x11) arrives, the JTAG_TAP will
    // output commands to the wishbone master here. The wishbone master
    // talks to the RISCV DM which is a wishbone slave.
    .start_read_transaction_o(start_read_transaction),
    .start_write_transaction_o(start_write_transaction),

    .addr_o(wishbone_addr), // address within the slave to write to/read from
    .write_transaction_data_o(wishbone_tx_data) // data to write into the wishbone slave through the master

);

endmodule