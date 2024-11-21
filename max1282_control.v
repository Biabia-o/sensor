module max1282_control(
    input 		wire 		sys_clk			,// 主时钟信号
    input 		wire 		sys_rst_n		,// 复位信号（低电平有效）
	 input 		wire 		dout				,// 数据输出
	 input 		wire 		SSTRB				,//SSTRB拉高一个时钟周期后输出采集的数据	

    output 		reg 		cs_n				,// 芯片选择，低电平有效
    output 		wire 		sclk				,// 串行时钟
    output 		reg 		din				,// 数据输入
	//MAX1282采集12bit数据，补齐16位
	 output 		reg 		[7:0]data_1_H		,//高八位
	 output 		reg 		[7:0]data_2_H		,
	 output 		reg 		[7:0]data_3_H		,
	 output 		reg 		[7:0]data_4_H		,
	 output 		reg 		[7:0]data_1_L		,//低八位
	 output 		reg 		[7:0]data_2_L		,
	 output 		reg 		[7:0]data_3_L		,
	 output 		reg 		[7:0]data_4_L		,
	 output		reg 		uart_txen

);

// 定义控制字格式
localparam  		START_BIT = 1'b1;               // 开始位
localparam  		UNI_BIP_BIT = 1'b1;             // 单端/伪差分模式位
localparam  		SGL_DIF_BIT = 1'b1;             // 单端/差分模式位
localparam [1:0]  PD1_PD0_BITS = 2'b11;          // 电源模式位（正常操作）
// 通道选择位
localparam [2:0] CHANNEL_SELECT_CH0 = 3'b001;
localparam [2:0] CHANNEL_SELECT_CH1 = 3'b101;
localparam [2:0] CHANNEL_SELECT_CH2 = 3'b010;
localparam [2:0] CHANNEL_SELECT_CH3 = 3'b110;

// 状态机状态定义
localparam 		  IDLE = 3'b000,
                 SELECT_CHANNEL = 3'b001,
                 WRITE_CONTROL_WORD = 3'b010,
                 WAIT_FOR_CONV = 3'b011,
                 READ_DATA = 3'b100;

reg [2:0] state = IDLE;    // 增加一个状态位以支持READ_DATA状态
reg [7:0] control_word;   // 控制字寄存器
reg [15:0] out_data;      // 存储ADC数据，12位数据加4位未使用的尾随位
reg [1:0] sel;			     // 通道选择，2位
reg [4:0]read_count;


integer i;
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        // 复位操作
        din <= 1'b0;
        state <= IDLE;
        out_data <= 16'b0000_0000_0000_0000;
        control_word <= 8'b00000000;
		  i <= 0;
		  read_count <= 0;  // 重置读取计数器
    end else begin
        case (state)
            IDLE:begin
                if (i < 4) begin
                    state <= SELECT_CHANNEL;
						  sel <= i[1:0];
                end else begin
                    i <= 0; // 重置通道计数器
                    state <= IDLE;
                end
            end
            SELECT_CHANNEL: begin
                // 根据通道计数器i选择通道
                case (sel)
                    0: control_word <= {START_BIT , CHANNEL_SELECT_CH0 , SGL_DIF_BIT , UNI_BIP_BIT , PD1_PD0_BITS};
                    1: control_word <= {START_BIT , CHANNEL_SELECT_CH1 , SGL_DIF_BIT , UNI_BIP_BIT , PD1_PD0_BITS};
                    2: control_word <= {START_BIT , CHANNEL_SELECT_CH2 , SGL_DIF_BIT , UNI_BIP_BIT , PD1_PD0_BITS};
                    3: control_word <= {START_BIT , CHANNEL_SELECT_CH3 , SGL_DIF_BIT , UNI_BIP_BIT , PD1_PD0_BITS};
                    default: control_word <= {START_BIT , CHANNEL_SELECT_CH0 , SGL_DIF_BIT , UNI_BIP_BIT , PD1_PD0_BITS};
                endcase
                state <= WRITE_CONTROL_WORD;
            end
            WRITE_CONTROL_WORD: begin
							din <= control_word[7]; // 发送最高位
							control_word <= control_word << 1; // 左移控制字，准备发送下一位
							if (control_word == 8'b0000_0000) begin
								state <= WAIT_FOR_CONV; // 发送完毕，等待转换
							end
						end
            WAIT_FOR_CONV: begin
							if (SSTRB) begin
								// SSTRB信号拉高表示转换已经开始
								state <= READ_DATA;
							end else begin
								state <= state;
							end
						end
            READ_DATA: begin
                // 读取12位ADC数据
							if (read_count < 16) begin  // 读取12位数据+4位未使用的尾随位
                        out_data <= {out_data[14:0], dout};  // 移位读取数据
                        read_count <= read_count + 1;  // 增加读取计数器
                     end
                     if (read_count == 15) begin  // 检查是否读取完毕
								i <= i + 1;
                        state <= IDLE;  // 返回到IDLE状态
                        read_count <= 0;  // 重置读取计数器
                     end
                end
            default : state <= IDLE;
        endcase
    end
end

assign sclk = ~sys_clk;


// CS信号在每个通道转换开始时拉低，转换结束时拉高
always @(posedge sys_clk or negedge sys_rst_n) 
	 if(sys_rst_n == 1'b0)
		  cs_n <= 1'b1;
    else if (state == WRITE_CONTROL_WORD || state == WAIT_FOR_CONV || state == READ_DATA) 
        cs_n <= 1'b0;
    else 
        cs_n <= 1'b1;
		  
		  
//data_1_H,data_1_L通道1对应CH_0
//data_2_H,data_2_L通道2对应CH_1	
//data_3_H,data_3_L通道2对应CH_2	
//data_4_H,data_4_L通道2对应CH_3		  
always @(posedge sys_clk or negedge sys_rst_n)begin
	if(sys_rst_n == 1'b0)begin
		data_1_H <= 8'd0;
		data_2_H <= 8'd0;
		data_3_H <= 8'd0;
		data_4_H <= 8'd0;
		data_1_L	<= 8'd0;
		data_2_L	<= 8'd0;
		data_3_L	<= 8'd0;
		data_4_L	<= 8'd0;
		uart_txen <= 1'b0;
		end
	else if(state == SELECT_CHANNEL)begin
		begin
		case(i[1:0])
		2'd0:begin
			data_4_H <= out_data[15:8];
			data_4_L <= out_data[7:0];
			end
		2'd1:begin
			data_1_H <= out_data[15:8];
			data_1_L <= out_data[7:0];
			end
		2'd2:begin
			data_2_H <= out_data[15:8];
			data_2_L <= out_data[7:0];
			end
		2'd3:begin
			data_3_H <= out_data[15:8];
			data_3_L <= out_data[7:0];
			end
		default : begin
		data_1_H <= data_1_H;
		data_1_L <= data_1_L;
		data_2_H <= data_2_H;
		data_2_L <= data_2_L;
		data_3_H <= data_3_H;
		data_3_L <= data_3_L;
		data_4_H <= data_4_H;
		data_4_L <= data_4_L;
		end
		endcase
		end
		uart_txen <= 1'b1;
		end
	else begin
		data_1_H <= data_1_H;
		data_2_H <= data_2_H;
		data_3_H <= data_3_H;
		data_4_H <= data_4_H;
		data_1_L <= data_1_L;
		data_2_L <= data_2_L;
		data_3_L <= data_3_L;
		data_4_L <= data_4_L;
		uart_txen <= 1'b0;
	end
end

endmodule
