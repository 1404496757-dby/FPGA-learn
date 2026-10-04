// Request/acknowledge toggle CDC for events, one outstanding event at a time.
// A source must hold s_valid until s_ready. Both domains must reset together.
module event_cdc(
    input wire arst_n, input wire s_clk, input wire d_clk,
    input wire s_valid, output wire s_ready, output reg d_pulse
);
    wire srst_n, drst_n;
    reset_sync rs(s_clk, arst_n, srst_n);
    reset_sync rd(d_clk, arst_n, drst_n);
    reg request_toggle, ack_toggle;
    wire request_sync, ack_sync;
    bit_sync request_cross(d_clk, drst_n, request_toggle, request_sync);
    bit_sync ack_cross(s_clk, srst_n, ack_toggle, ack_sync);
    assign s_ready = srst_n && (request_toggle == ack_sync);
    always @(posedge s_clk or negedge srst_n)
        if (!srst_n) request_toggle <= 0;
        else if (s_valid && s_ready) request_toggle <= ~request_toggle;
    always @(posedge d_clk or negedge drst_n)
        if (!drst_n) begin ack_toggle<=0; d_pulse<=0; end
        else begin
            d_pulse <= request_sync != ack_toggle;
            ack_toggle <= request_sync;
        end
endmodule
