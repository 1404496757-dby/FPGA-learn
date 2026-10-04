// Educational discrete PID: signed 16-bit error and Q7.8 coefficients.
// Sample period is absorbed into Ki (Ki*Ts) and Kd (Kd/Ts) by the caller.
// Integral and derivative are saturated to 16 bits BEFORE 16x16 products.
// Three 32-bit products, signed 34-bit sum, arithmetic truncation, output clamp.
// One outstanding sample, 3 compute cycles; output retained under backpressure.
// Integral limiting is not equivalent to a complete actuator anti-windup scheme.
module pid_q8 #(
    parameter integer I_LIMIT=4096, parameter integer OUT_MIN=-32768, parameter integer OUT_MAX=32767
)(
    input wire clk, input wire rst_n,
    input wire s_valid, output wire s_ready,
    input wire signed [15:0] error_value, kp, ki, kd,
    output reg m_valid, input wire m_ready, output reg signed [15:0] control,
    output reg saturated, output wire signed [15:0] integral_debug
);
    reg [1:0] state;
    reg signed [15:0] integral, previous_error;
    reg signed [31:0] p_product, i_product, d_product;
    reg signed [33:0] sum;
    reg signed [16:0] next_integral, derivative;
    reg signed [15:0] bounded_i, bounded_d;
    wire signed [33:0] scaled=sum>>>8;
    assign s_ready=rst_n && state==0 && !m_valid;
    assign integral_debug=integral;
    always @* begin
        next_integral=$signed({integral[15],integral})+$signed({error_value[15],error_value});
        derivative=$signed({error_value[15],error_value})-$signed({previous_error[15],previous_error});
        if(next_integral>I_LIMIT) bounded_i=I_LIMIT;
        else if(next_integral < -I_LIMIT) bounded_i=-I_LIMIT;
        else bounded_i=next_integral[15:0];
        if(derivative>32767) bounded_d=32767;
        else if(derivative < -32768) bounded_d=-32768;
        else bounded_d=derivative[15:0];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0; integral<=0; previous_error<=0; p_product<=0; i_product<=0; d_product<=0;
            sum<=0; m_valid<=0; control<=0; saturated<=0;
        end else begin
            if(m_valid && m_ready) m_valid<=0;
            case(state)
                0: if(s_valid && s_ready) begin
                    integral<=bounded_i; previous_error<=error_value;
                    p_product<=error_value*kp; i_product<=bounded_i*ki; d_product<=bounded_d*kd;
                    state<=1;
                end
                1: begin
                    sum<=$signed({{2{p_product[31]}},p_product})+
                         $signed({{2{i_product[31]}},i_product})+
                         $signed({{2{d_product[31]}},d_product});
                    state<=2;
                end
                2: begin
                    saturated<=0;
                    if(scaled>OUT_MAX) begin control<=OUT_MAX; saturated<=1; end
                    else if(scaled<OUT_MIN) begin control<=OUT_MIN; saturated<=1; end
                    else control<=scaled[15:0];
                    m_valid<=1; state<=0;
                end
                default: state<=0;
            endcase
        end
    end
    // synthesis translate_off
    initial if(I_LIMIT<1 || I_LIMIT>32767 || OUT_MIN < -32768 || OUT_MAX>32767 || OUT_MIN>=OUT_MAX)
        $fatal(1,"Invalid PID bounds");
    // synthesis translate_on
endmodule
