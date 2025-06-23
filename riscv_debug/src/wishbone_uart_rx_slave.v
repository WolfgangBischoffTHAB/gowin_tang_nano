module wishbone_uart_rx_slave 
(

    // input
    input wire clk_i, // clock input
	input wire rst_i, // asynchronous reset input, low active

    // input (slaves)
    input wire [31:0] addr_i,
    input wire we_i,
    input wire [31:0] data_i, // the RX slave does not use data_i
    input wire cyc_i,
    input wire stb_i,

    // wbi input custom
    input wire [7:0] slave_remote_data_source_in,

    // output (slaves)
    output wire [31:0] data_o, // the RX slave returns read RX data here
    output wire ack_o

);

reg [31:0] data_o_reg;
assign data_o = data_o_reg;

reg ack_o_reg;
assign ack_o = ack_o_reg;

localparam IDLE = 0;
localparam READ = 1;

// current and next_state
reg [1:0] cur_state = IDLE;
reg [1:0] next_state;

// next state logic
always @(posedge clk_i) 
begin
    
    // if reset is asserted, 
    if (rst_i) 
    begin
        // go back to IDLE state
        cur_state = IDLE;
    end    
    else 
    begin
        // else transition to the next state
        cur_state = next_state;
    end

end

always @(*)
begin

    case (cur_state)

        IDLE:
        begin
            // reset
            data_o_reg = ~32'b01;
            ack_o_reg = 0;

            // master starts a transaction
            if (cyc_i == 1 && stb_i == 1)
            begin
                next_state = READ;
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
                // present the read data
                data_o_reg = ~slave_remote_data_source_in;
                ack_o_reg = 1;

                next_state = READ;
            end
            else
            begin
                data_o_reg = ~32'b11; // output a dummy value
                ack_o_reg = 0;

                next_state = IDLE;
            end            
        end

        default:
        begin
            data_o_reg = ~32'b100;
            ack_o_reg = 0;
            next_state = cur_state;
        end

    endcase

end

endmodule