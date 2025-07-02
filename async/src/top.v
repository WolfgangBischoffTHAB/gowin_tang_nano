module top (

    // input
    input sys_clk,          // clk input
    input sys_rst_n,        // reset input

    input async_in,

    // output
    output wire [5:0] led,    // 6 LEDS pin
    output            uart_tx // UART TX
);

reg [5:0] led_reg;
assign led = led_reg;

reg async_in_old = 0;

always @(posedge sys_clk)
begin

    if (sys_rst_n == 0)
    begin
        led_reg = ~6'b000000;
        tx_data = 8'h00;
    end
    else
    begin

        // whenever the asyncronous input changes, update the LED[0]
        if (async_in == 1)
        begin
            led_reg[0] = ~1'b1;            
        end
        else
        begin
            led_reg[0] = ~1'b0;
        end

        // use a toggle bit to react to a change of the input signal only once
        if (async_in_old != async_in)
        begin
            // remember new state
            async_in_old = async_in;

            // increment the value that is sent over UART
            tx_data = tx_data + 1;

            // trigger sending a byte over UART
            uart_send_data = ~uart_send_data;
        end

        // toggle the led[5] if the counter has reached a certain value
        if (counter == 24'd1349_9999)
        begin
            led_reg[5] = ~led_reg[5];
        end

    end

end




reg [23:0] counter;

// update the counter variable after a certain amount of time
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        counter <= 24'd0;
    else if (counter < 24'd1349_9999) // 0.5s delay
        counter <= counter + 1'b1;
    else
        counter <= 24'd0;
end

/*
// update the LEDs
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        led <= 6'b111110;
    else if (counter == 24'd1349_9999)       // 0.5s delay
        led[5:0] <= {led[4:0],led[5]};    // left to right
        //led[5:0] <= {led[0], led[5:1]};     // right to left
    else
        led <= led;
end
*/


//
// UART
//

parameter                        CLK_FRE  = 27; // Mhz. The Tang Nano 9K has a 27 Mhz clock source on board
parameter                        UART_FRE = 115200; // baudrate

reg uart_send_data = 0;
reg uart_send_data_old = 0;

reg[7:0]                         tx_data = 8'h00;
reg[7:0]                         tx_str;
reg                              tx_data_valid;
wire                             tx_data_ready;
reg[7:0]                         tx_cnt;

always @(posedge sys_clk)
begin

    // use toggle bit to execute a send command once only
    if (uart_send_data_old != uart_send_data)
    begin
        // remember state to not repeat the command again
        uart_send_data_old = uart_send_data;

        // tell the tx UART that data is ready for transmission
        tx_data_valid <= 1'b1;
    end
    else
    begin
        tx_data_valid <= 1'b0;
    end

end

uart_tx#
(
	.CLK_FRE(CLK_FRE),
	.BAUD_RATE(UART_FRE)
) uart_tx_inst
(
    // input
	.clk                        (sys_clk),
	.rst_n                      (sys_rst_n),
	.tx_data                    (tx_data),
	.tx_data_valid              (tx_data_valid),

    // output
	.tx_data_ready              (tx_data_ready),
	.tx_pin                     (uart_tx)
);

endmodule