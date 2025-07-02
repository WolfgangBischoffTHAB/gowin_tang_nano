module mux2 #(parameter WIDTH = 8) (

    // input
    input wire [WIDTH-1:0] d0,  // selectable input 0
    input wire [WIDTH-1:0] d1,  // selectable input 1
    input wire s,               // selector (0 or 1)

    // output
    output wire [WIDTH-1:0] y   // output

);

    assign y = s ? d1 : d0;

endmodule