// Complementary PWM study, NOT a TB6600 STEP/DIR controller.
// 50MHz / 2500 = 20kHz; 50 clocks = 1us dead time.
// New duty is latched at period boundaries; duty=0/PERIOD are defined.
module pwm_deadtime #(
    parameter PERIOD=2500, parameter DEAD_CYCLES=50
)(
    input wire clk, input wire rst_n, input wire [15:0] duty,
    output reg pwm_high, output reg pwm_low
);
    localparam CW=$clog2(PERIOD), DW=$clog2(DEAD_CYCLES+1);
    reg [CW-1:0] phase;
    reg [15:0] active_duty;
    reg pending;
    reg [DW-1:0] blank_count;
    wire desired=phase<active_duty;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            phase<=0; active_duty<=0; pending<=0; blank_count<=DEAD_CYCLES;
            pwm_high<=0; pwm_low<=0;
        end else begin
            if(phase==PERIOD-1) begin
                phase<=0; active_duty<=duty>PERIOD ? PERIOD : duty;
            end else phase<=phase+1'b1;
            if(desired!=pending) begin
                pwm_high<=0; pwm_low<=0; pending<=desired; blank_count<=DEAD_CYCLES;
            end else if(blank_count!=0) begin
                pwm_high<=0; pwm_low<=0; blank_count<=blank_count-1'b1;
            end else begin pwm_high<=pending; pwm_low<=!pending; end
        end
    end
    // synthesis translate_off
    initial if(PERIOD<2 || PERIOD>65535 || DEAD_CYCLES<1 || DEAD_CYCLES>=PERIOD)
        $fatal(1,"Invalid PWM period/dead-time settings");
    // synthesis translate_on
endmodule
