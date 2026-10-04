# ACX750 Verilog学习工程

目标芯片：`xc7a35tfgg484-2`。
本机工具：Vivado 2018.3，`E:/lll/FPGA/Xilinx/Vivado/2018.3/bin`。

2026-10-03新搭建的学习与复现实现。开源UART、SPI、JPEG-LS核心保留源码与许可证；新写的FIFO、适配器、系统调度、协议、定点运算和测试单独放在rtl/sim/host。

## 文件布局

| 目录 | 内容 |
|---|---|
| rtl/common | 同步BRAM FIFO、Gray异步FIFO、两级同步、复位同步、事件握手CDC |
| rtl/comm | UART命令/FIFO/SPI适配与ACX750通信顶层 |
| rtl/image | 输入图像缓存、JPEG-LS整帧码流缓存、CRC与回传、25MHz板级顶层 |
| rtl/interview | 有符号Q7.8 PID、互补PWM与死区，作为独立学习练习 |
| vendor | 保持原样的开源核及LICENSE；来源见SOURCE_MANIFEST.json |
| sim | SystemVerilog自检查测试平台；设计RTL为Verilog |
| constraints | ACX750引脚/时钟/同步器例外与Gray总线约束学习示例 |
| scripts | 一键仿真与Vivado工程/bitstream生成 |
| host | PC串口客户端、CRC协议、软件解码逐像素验证 |
| runs / builds | 每次运行的新目录、日志、结果及报告 |
| output | 最终验证版本的bitstream与实现报告副本 |

第一次使用先看`docs/从零跑通与学习顺序.md`，最终验证结果见`docs/验证结果.md`。

## 先运行仿真

```powershell
Set-Location -LiteralPath 'F:\2_DBY\FPGA\JL\projects\jianli'
& '.\scripts\run_sim.ps1' -Test all
```

只学习某一部分：`-Test common`、`comm`、`uart_board`、`image`、`interview`、`spi`。
脚本检查工具退出码及PASS标记；image测试额外调用FFmpeg独立解码，逐像素比较4张图。
默认Python为`python`，FFmpeg为现有`C:/Program Files/ffmpeg-7.0.2-full_build/bin/ffmpeg.exe`，可用参数覆盖。

测试覆盖：

- common：同步FIFO满空/回绕/随机读写/反压/同拍进出，异步FIFO独立时钟400字，事件CDC40次。
- comm：回显、SPI交换、丢字节统计读取、错误校验/未知命令、半包超时、回包暂停。
- uart_board：115200 8N1串行收发经过完整通信顶层，回显与SPI内部回环回包比较。
- image：常量/渐变/棋盘/伪随机4张64×64灰度图，输出暂停；输入CRC损坏拒绝；小缓存溢出报错；半帧超时；独立解码逐像素一致。
- interview：16×16有符号乘法、34位累加、Q8截断、正负输出限幅、积分限幅、输出暂停；20kHz互补PWM、零/满占空比和至少1us死区。
- spi：参考主机的模式0/1/2/3各16字节回环。

仿真通过记录：`verification_all.json`。这不替代真实板上测试，也不包含模拟亚稳态物理行为或形式验证。

## 项目一：通信接口与FIFO

结构：PC → UART RX → 新写同步FIFO → 命令FSM → 回显/单字节SPI → 回包FSM → UART TX → PC。
板级顶层：`rtl/comm/comm_acx750_top.v`，单50MHz时钟。
SPI在此顶层做内部MOSI到MISO回环，未使用外部从设备。`comm_service.v`保留外部SPI端口，接外设时还需按原理图选择GPIO、约束并验证板级时序。

请求5字节：`A5 opcode sequence data xor`，xor为前4字节异或。
回复5字节：`5A status sequence result xor`。

| opcode/status | 含义 |
|---|---|
| 00 | 回显data |
| 01 | SPI交换1字节并返回结果；默认SPI模式0、50MHz/(2×5)=5MHz |
| 02 | 返回累计RX丢字节计数低8位 |
| E1 | 校验错误，结果0 |
| E2 | 未知命令，结果0 |

示例：请求`A5 00 01 13 B7`，回复`5A 00 01 13 48`。
PC采用停止等待：收到一包回复后再发下一包。半包默认100ms超时，随后重新搜索A5。
每个包只有一个数据字节，适合学习/调试，不把它当作大吞吐数据采集协议。

### FIFO与反压应如何解释

`stream_fifo.v`用同步RAM读取与一个输出寄存器实现ready/valid。
`level=RAM中未预取字数+m_valid`，总容量是DEPTH，包含输出槽。
预取把RAM数据搬到输出槽，不等同于下游消费；消费条件是`m_valid && m_ready`。
输出暂停时保持valid和data；FIFO满但同拍消费时允许写入；没有复位整个RAM，只清空指针/计数/有效状态。
BRAM地址和控制寄存器使用同步复位，避免异步复位跳变直接影响RAM控制。

UART外部波形不能由内部ready暂停。接收核FIFO_EA=0时输出是单拍事件；FIFO满时，该字节被丢弃并记录。
想持续可靠传输，必须保证长期输入速率不超过输出能力，并设计ACK/信用/RTS-CTS等外部流控。增加FIFO只吸收有限突发。
115200/8N1理论字符载荷11520字节/秒；5字节请求+5字节回复的停止等待单字节协议还承担包开销和往返延迟。

## 项目二：JPEG-LS图像编码与整帧缓存

结构：PC原始灰度图 → UART/FIFO → 4KiB输入BRAM → CRC确认 → JPEG-LS → 32KiB码流BRAM → 回包/UART → PC独立解码。
板级顶层：`rtl/image/image_acx750_top.v`；Clocking Wizard将50MHz晶振转为25MHz，UART和编码逻辑共用25MHz，不需要在这条链路中虚构异步时钟域。

初版固定64×64、8bit灰度、NEAR=0。服务模块可在符合参数检查时改尺寸，但PC客户端与内存预算也必须同时修改。
输入每2拍送1像素，包含真实的同步BRAM读取等待；核初始化i_sof保持368拍。
开源核的复位由本地时钟寄存器驱动，避免其异步复位分支在综合合并后把异步输入直接接到BRAM输出寄存器复位端。
核心没有输出ready：编码期间每个有效16位输出都捕获；低字节先回传。缓存满时标记失败，继续排空编码核直到帧结束，随后返回E3，不返回截断文件。
32KiB是初版预算和保护上限，不声称已经推导出所有尺寸/内容的最坏码长。

请求：`4A 4C seq [4096像素] CRC低 CRC高`。
请求CRC覆盖seq和像素，CRC16-CCITT-FALSE，初始FFFF，多项式1021，不反射。
回复：`4A 53 seq status len低 len高 [len字节JLS] CRC低 CRC高`。
回复CRC覆盖seq/status/len/JLS，不含前两个魔数；回复长度采用小端。
状态：00成功，E1输入CRC错，E3码流缓存溢出，F1半帧超时（默认0.5秒没有下一个字节）。错误回复长度为0。
仅允许一帧在途，收到回复前不要发送下一帧；UART FIFO无法替外部主机提供无限背压。

已使用测试图验证：原始均4096字节；常量编码52、渐变634、棋盘610、噪声4750字节。噪声可能膨胀，因此不能假设压缩后必定更小。

### 算法读码顺序

先读vendor/jls/jls_encoder.v中的`func_predictor`和linebuffer，再读上下文量化、误差符号处理、N/A/B/C更新、Golomb-Rice与游程编码、bit打包及头尾。
逐个信号标注：含义、位宽/符号、更新条件、延迟。通过tb_image观察原图→码流→软件解码的闭环。
ImCvt的软件编码可辅助理解；它不支持普通.jls解码。本工程用本机FFmpeg完成独立解码。
当前没有SD卡写入、DDR3、摄像头、CAN、编码器测速或真实电机闭环，不能由本工程推断这些功能已经实现。

## 生成可下载的工程

```powershell
& '.\scripts\build.ps1' -Project comm
& '.\scripts\build.ps1' -Project image
```

每次生成新的builds子目录，包含.xpr、实现报告和.bit。脚本不连接或烧写硬件。
ACX750管脚依据本地ACX750_CB_PIN.xdc：W19时钟、D21低有效S0、L21 RX、M21 TX、U22/V22 LED。
ACX750-CORE.pdf第4页确认CFGBVS及Bank0供电接VCC3P3，约束设置CFGBVS=VCCO、CONFIG_VOLTAGE=3.3。
UART RX例外只到第一级同步器D；第二级与下游保持正常时序分析。TX/LED给出明确输出预算，复位异步输入通过专用同步释放链处理。
`report_cdc`不报告没有输入时钟定义的UART物理输入，不能把空CDC报告当作无风险证明。

上板步骤：用Vivado打开对应.xpr，Hardware Manager通过JTAG加载对应.bit，使用板载USB-UART的实际COM口。两个顶层是分别加载的工程。
PC串口客户端需要pyserial；当前默认Python未安装，`host/requirements.txt`列出依赖。

```powershell
python -m pip install -r '.\host\requirements.txt'
python '.\host\comm_client.py' --port COM5 --mode echo --value 0x13
python '.\host\comm_client.py' --port COM5 --mode spi --value 0xC1
python '.\host\comm_client.py' --port COM5 --mode status
python '.\host\image_client.py' --port COM5 --pattern gradient --output '.\board_capture'
```

COM5仅示例，必须改为实际端口。image_client保存原始像素、完整回包、.jls、解码像素，只有CRC和逐像素检查都通过才打印PASS_BOARD_IMAGE。

## 面试补充模块

`async_fifo.v`用于两个独立时钟：binary指针寻址、Gray指针跨域、双级同步、next指针比较满空。读接口是读请求/延迟有效，不是可任意暂停的输出stream。
`wr_valid&&wr_ready`才写；`rd_en&&!rd_empty`才读；空读不发valid，旧rd_data的位值不代表新数据。满空在各自域内保守生效，远端指针同步需要时钟沿，不会写入后马上跨域变为非空。
两域共用复位，各自同步释放，再在时钟沿清空本域状态。只复位一侧的在线操作不受支持。
Gray总线约束辅助过程放在constraints/async_fifo_constraints.tcl，当前两个板级主工程未实例化异步FIFO；该辅助约束未作为这两个bitstream的CDC实现证明。

`event_cdc.v`使用req/ack翻转握手，一次只允许一个未确认事件，解决短脉冲直接两级同步可能漏采的问题。
`pid_q8.v`的16×16乘法结果32位，三项显式符号扩展后用34位相加；右移8位取整，再判断输出范围，最后截取。负值右移为算术截断，不是四舍五入。
积分16位限幅，误差差分先扩17位再限16位；调用方把采样周期折入Ki/Kd。输入接收→乘法→求和→输出，共分3个处理阶段，输出等待时保持稳定。未验证真实被控对象的稳定性或响应时间。
`pwm_deadtime.v`的默认参数是50MHz/2500=20kHz，50拍=1us；占空比只在周期边界更新，两路互补输出不会同时为高。
该PWM是互补功率开关练习，TB6600主要使用STEP/DIR，不能把这段代码当作实际树莓派注射平台的控制器。

对应追问、正确解释和波形实验见`docs/面试追问到代码.md`。

## 代码来源与能力表述

新增代码由本次协作编写，不应描述为本人过去独立实现。你可以复现、理解、修改，再记录自己的贡献。
vendor核按原仓库LICENSE保留，整体学习工程采用GPL-3.0，SPI部分保留MIT许可。
源码来源、提交及文件哈希见SOURCE_MANIFEST.json；最终验证与交付索引见DELIVERY_STATUS.json。
