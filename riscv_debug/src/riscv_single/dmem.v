module dmem(

    // input
    input wire clk,
    input wire reset_n,
    input wire we,
    input wire [31:0] a, 
    input wire [31:0] wd,

    // output
    output wire [31:0] rd,
    output wire led

);

    reg [31:0] RAM[63:0];

    reg temp_led = 0;
    assign led = temp_led;

    // read
    assign rd = RAM[a[31:2]]; // word aligned  

    // write
    always @(posedge clk)
    begin
        if (we)
        begin
            RAM[a[31:2]] <= wd;
        end
    end

    always @(posedge we)
    begin
        temp_led = ~temp_led;
    end

endmodule