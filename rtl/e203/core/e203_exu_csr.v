 /*                                                                      
 Copyright 2017 Silicon Integrated Microelectronics, Inc.                
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
  Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */                                                                      
                                                                         
                                                                         
                                                                         
//=====================================================================
//--        _______   ___
//--       (   ____/ /__/
//--        \ \     __
//--     ____\ \   / /
//--    /_______\ /_/   MICROELECTRONICS
//--
//=====================================================================
//
// Designer   : Bob Hu
//
// Description:
//  The module to implement the core's CSRs
//
// ====================================================================
`include "e203_defines.v"


//csr: control status register
//关于每个CSR寄存器的功能详见书P374表B-1 蜂鸟E200支持的CSR寄存器列表
module e203_exu_csr(
  input nonflush_cmt_ena,
  output eai_xs_off,

  //来自ALU的csr读写使能信号
  input csr_ena,
  //CSR写操作指示信号
  input csr_wr_en,
  //CSR读操作指示信号
  input csr_rd_en,
  //csr寄存器的地址序号
  input [12-1:0] csr_idx,

  //是否是合法的csr访问
  output csr_access_ilgl,
  output tm_stop,
  output core_cgstop,
  output tcm_cgstop,
  output itcm_nohold,
  output mdv_nob2b,

  //从csr读出的数据
  output [`E203_XLEN-1:0] read_csr_dat,
  //要写入csr的数据
  input  [`E203_XLEN-1:0] wbck_csr_dat,
   
  input  [`E203_HART_ID_W-1:0] core_mhartid,
  input  ext_irq_r,
  input  sft_irq_r,
  input  tmr_irq_r,

  //机器模式中断使能寄存器 mie (Machine Interrupt Enable Registers)可以用于控制中断的屏蔽。
  output status_mie_r,
  //mie的一个域， 机器模式计时器中断使能信号
  output mtie_r,
  //mie的一个域， 机器模式软件中断使能信号
  output msie_r,
  //mie的一个域，机器模式外部中断(Machine External Interrupt)使能信号
  output meie_r,

  //dcsr使能信号，进入调试模式(debug mode)时将引发进入调试模式的触发原因保存到CSR寄存器dcsr中。
  output wr_dcsr_ena    ,
  //dpc使能信号，进入调试模式(debug mode)时将处理器正在执行的指令PC保存到CSR寄存器dpc中。
  output wr_dpc_ena     ,
  output wr_dscratch_ena,


  input [`E203_XLEN-1:0] dcsr_r    ,
  input [`E203_PC_SIZE-1:0] dpc_r     ,
  input [`E203_XLEN-1:0] dscratch_r,

  output [`E203_XLEN-1:0] wr_csr_nxt    ,

  //是否是调试模式
  input  dbg_mode,
  input  dbg_stopcycle,

  //risc-v 特权模式
  //u: user mode
  //s: supervisor mode
  //m: machine mode
  //h: hypervisor mode
  output u_mode,
  output s_mode,
  output h_mode,
  output m_mode,

  input [`E203_ADDR_SIZE-1:0] cmt_badaddr,
  input cmt_badaddr_ena,
  input [`E203_PC_SIZE-1:0] cmt_epc,
  input cmt_epc_ena,
  input [`E203_XLEN-1:0] cmt_cause,
  input cmt_cause_ena,
  input cmt_status_ena,
  input cmt_instret_ena,

  input                      cmt_mret_ena,
  output[`E203_PC_SIZE-1:0]  csr_epc_r,
  output[`E203_PC_SIZE-1:0]  csr_dpc_r,
  //机器模式异常入口基地址寄存器 mtvec (Machine Trap-Vector Base-Address Register）的 CSR 寄存器指定
  // mtvec 寄存器是一个可读可写的 CSR 寄存器，因此软件可以编程更改其中的值， 详见书P244 
  // mtvec值的输出端口
  output[`E203_XLEN-1:0]     csr_mtvec_r,


  input  clk_aon,
  input  clk,
  input  rst_n

  );


//设置为合法的csr访问
assign csr_access_ilgl = 1'b0
                ;

// Only toggle when need to read or write to save power
//判断是否能够写入数据
wire wbck_csr_wen = csr_wr_en & csr_ena & (~csr_access_ilgl);
//判断是否能够读取数据
wire read_csr_ena = csr_rd_en & csr_ena & (~csr_access_ilgl);

//判断特权模式
wire [1:0] priv_mode = u_mode ? 2'b00 : 
                       s_mode ? 2'b01 :
                       h_mode ? 2'b10 : 
                       m_mode ? 2'b11 : 
                                2'b11;

//机器模式异常值寄存器 mtval (Machine Trap Value Register )
//在进入异常时，硬件将自动更新机器模式状态寄存器 mstatus(Machine Status Register)的某些域。详见书P246
//0x000 URW ustatus User status register.
//    * Since we support the user-level interrupt, hence we need to support UIE
//0x300 MRW mstatus Machine status register.
//判断是不是操作ustatus寄存器
wire sel_ustatus = (csr_idx == 12'h000);
//判断是不是操作mstatus寄存器
wire sel_mstatus = (csr_idx == 12'h300);

//判断是不是读取ustatus寄存器
wire rd_ustatus = sel_ustatus & csr_rd_en;
//判断是不是读取mstatus寄存器
wire rd_mstatus = sel_mstatus & csr_rd_en;
//判断是不是写入ustatus寄存器
wire wr_ustatus = sel_ustatus & csr_wr_en;
//判断是不是写入mstatus寄存器
wire wr_mstatus = sel_mstatus & csr_wr_en;


/////////////////////////////////////////////////////////////////////
// Note: the below implementation only apply to Machine-mode config,
//       if other mode is also supported, these logics need to be updated

//////////////////////////
// Implement MPIE field
//MPIE域的作用是在异常结束之后，能够使用MPIE的值恢复出异常发生之前的MIE值
//mstatus 寄存器中的MPIE和MPP域分别用于保存进入异常之前 MIE 域和特权模式(Privilege Mode)的值 。
wire status_mpie_r;
    // The MPIE Feilds will be updates when: 
wire status_mpie_ena  = 
        // The CSR is written by CSR instructions
        (wr_mstatus & wbck_csr_wen) |
        // The MRET instruction commited
        cmt_mret_ena |
        // The Trap is taken
        cmt_status_ena;

wire status_mpie_nxt    = 
    //   See Priv SPEC:
    //       When a trap is taken from privilege mode y into privilege
    //       mode x, xPIE is set to the value of xIE;
    // So, When the Trap is taken, the MPIE is updated with the current MIE value
    cmt_status_ena ? status_mie_r :
    //   See Priv SPEC:
    //       When executing an xRET instruction, supposing xPP holds the value y, xIE
    //       is set to xPIE; the privilege mode is changed to y; 
    //       xPIE is set to 1;
    // So, When the MRET instruction commited, the MPIE is updated with 1
    cmt_mret_ena  ? 1'b1 :
    // When the CSR is written by CSR instructions
    (wr_mstatus & wbck_csr_wen) ? wbck_csr_dat[7] : // MPIE is in field 7 of mstatus
                  status_mpie_r; // Unchanged 

sirv_gnrl_dfflr #(1) status_mpie_dfflr (status_mpie_ena, status_mpie_nxt, status_mpie_r, clk, rst_n);

//////////////////////////
// Implement MIE field
//机器模式中断使能寄存器 mie (Machine Interrupt Enable Registers)可以用于控制中断的屏蔽。
    // The MIE Feilds will be updates same as MPIE
wire status_mie_ena  = status_mpie_ena; 
wire status_mie_nxt    = 
    //   See Priv SPEC:
    //       When a trap is taken from privilege mode y into privilege
    //       mode x, xPIE is set to the value of xIE,
    //       xIE is set to 0;
    // So, When the Trap is taken, the MIE is updated with 0
     cmt_status_ena ? 1'b0 :
    //   See Priv SPEC:
    //       When executing an xRET instruction, supposing xPP holds the value y, xIE
    //       is set to xPIE; the privilege mode is changed to y, xPIE is set to 1;
    // So, When the MRET instruction commited, the MIE is updated with MPIE
    cmt_mret_ena ? status_mpie_r :
    // When the CSR is written by CSR instructions
    (wr_mstatus & wbck_csr_wen) ? wbck_csr_dat[3] : // MIE is in field 3 of mstatus
                  status_mie_r; // Unchanged 

sirv_gnrl_dfflr #(1) status_mie_dfflr (status_mie_ena, status_mie_nxt, status_mie_r, clk, rst_n);

//////////////////////////
// Implement SD field
//
//  See Priv SPEC:
//    The SD bit is read-only 
//    And is set when either the FS or XS bits encode a Dirty
//      state (i.e., SD=((FS==11) OR (XS==11))).
wire [1:0] status_fs_r;
wire [1:0] status_xs_r;
wire status_sd_r = (status_fs_r == 2'b11) | (status_xs_r == 2'b11);

//////////////////////////
// Implement XS field
//
//  See Priv SPEC:
//    XS field is read-only
//    The XS field represents a summary of all extensions' status
    // But in E200 we implement XS exactly same as FS to make it usable by software to 
    //   disable extended accelerators
`ifndef E203_HAS_EAI
   // If no EAI coprocessor interface configured, the XS is just hardwired to 0
assign status_xs_r = 2'b0; 
assign eai_xs_off = 1'b0;// We just make this signal to 0
`endif

//////////////////////////
// Implement FS field
//

`ifndef E203_HAS_FPU
   // If no FPU configured, the FS is just hardwired to 0
assign status_fs_r = 2'b0; 
`endif

//////////////////////////
// Pack to the full mstatus register
//
wire [`E203_XLEN-1:0] status_r;
assign status_r[31]    = status_sd_r;                        //SD
assign status_r[30:23] = 8'b0; // Reserved
assign status_r[22:17] = 6'b0;               // TSR--MPRV
assign status_r[16:15] = status_xs_r;                        // XS
assign status_r[14:13] = status_fs_r;                        // FS
//mstatus寄存器中的MPIE和MPP域分别用于保存进入异常之前 MIE 域和特权模式(Privilege Mode)的值。
assign status_r[12:11] = 2'b11;              // MPP 
assign status_r[10:9]  = 2'b0; // Reserved
assign status_r[8]     = 1'b0;               // SPP
assign status_r[7]     = status_mpie_r;                      // MPIE
assign status_r[6]     = 1'b0; // Reserved
assign status_r[5]     = 1'b0;               // SPIE 
assign status_r[4]     = 1'b0;               // UPIE 
assign status_r[3]     = status_mie_r;                       // MIE
assign status_r[2]     = 1'b0; // Reserved
assign status_r[1]     = 1'b0;               // SIE 
assign status_r[0]     = 1'b0;               // UIE 

wire [`E203_XLEN-1:0] csr_mstatus = status_r;

//0x004 URW uie User interrupt-enable register.
//    * Since we dont delegate interrupt to user mode, hence it is as all 0s
//0x304 MRW mie Machine interrupt-enable register.
wire sel_mie = (csr_idx == 12'h304);
//读取mie，选择mie并且读取使能为1
wire rd_mie = sel_mie & csr_rd_en;
//写入mie，选择mie并且写入使能为1
wire wr_mie = sel_mie & csr_wr_en;
//mie_ena: 写入使能信号，需要写入mie并且能够写入(允许写入)
wire mie_ena = wr_mie & wbck_csr_wen;
wire [`E203_XLEN-1:0] mie_r;
wire [`E203_XLEN-1:0] mie_nxt;
assign mie_nxt[31:12] = 20'b0;
//设置MIE相应的域的写入的值
assign mie_nxt[11] = wbck_csr_dat[11];//MEIE
assign mie_nxt[10:8] = 3'b0;
assign mie_nxt[ 7] = wbck_csr_dat[ 7];//MTIE
assign mie_nxt[6:4] = 3'b0;
assign mie_nxt[ 3] = wbck_csr_dat[ 3];//MSIE
assign mie_nxt[2:0] = 3'b0;
//                                      写入使能  写入的值  保存的值 时钟  复位
sirv_gnrl_dfflr #(`E203_XLEN) mie_dfflr (mie_ena, mie_nxt, mie_r, clk, rst_n);
wire [`E203_XLEN-1:0] csr_mie = mie_r;

//选择mie寄存器中对应的域
//meie:机器外部中断使能
assign meie_r = csr_mie[11];
//mtie:机器时间中断使能
assign mtie_r = csr_mie[ 7];
//msie:机器软件中断使能
assign msie_r = csr_mie[ 3];

//MIP: 机器模式中断等待寄存器（ Machine Interrupt Pending Registers)
//0x044 URW uip User interrupt pending.
//  We dont support delegation scheme, so no need to support the uip
//0x344 MRW mip Machine interrupt pending
wire sel_mip = (csr_idx == 12'h344);
wire rd_mip = sel_mip & csr_rd_en;
//wire wr_mip = sel_mip & csr_wr_en;
// The MxIP is read-only
//meip: 机器模式外部中断等待寄存器
wire meip_r;
//msip: 机器模式软件中断等待寄存器(Machine-mode Software Interrupt Pending Register)
wire msip_r;
//mtip: 机器模式时间中断等待寄存器
wire mtip_r;
//使用带有复位(reset)的dff分别实现meip、msip、mtip域
sirv_gnrl_dffr #(1) meip_dffr (ext_irq_r, meip_r, clk, rst_n);
sirv_gnrl_dffr #(1) msip_dffr (sft_irq_r, msip_r, clk, rst_n);
sirv_gnrl_dffr #(1) mtip_dffr (tmr_irq_r, mtip_r, clk, rst_n);

wire [`E203_XLEN-1:0] ip_r;
//设置中断等待寄存器的各个域的值，未使用的设置为0
assign ip_r[31:12] = 20'b0;
assign ip_r[11] = meip_r;
assign ip_r[10:8] = 3'b0;
assign ip_r[ 7] = mtip_r;
assign ip_r[6:4] = 3'b0;
assign ip_r[ 3] = msip_r;
assign ip_r[2:0] = 3'b0;
//csr_mip用于将中断等待寄存器的值传递给多路选择器，用于输出信号
wire [`E203_XLEN-1:0] csr_mip = ip_r;

//机器模式异常入口基地址寄存器 mtvec (Machine Trap-Vector Base-Address Register）
//0x005 URW utvec User trap handler base address.
//  We dont support user trap, so no utvec needed
//0x305 MRW mtvec Machine trap-handler base address.
//是否选择mtvec寄存器 
wire sel_mtvec = (csr_idx == 12'h305);
//读取mtvec寄存器
wire rd_mtvec = csr_rd_en & sel_mtvec;
`ifdef E203_SUPPORT_MTVEC //{
//写入mtvec寄存器
wire wr_mtvec = sel_mtvec & csr_wr_en;
//mtvec寄存器写入使能信号
wire mtvec_ena = (wr_mtvec & wbck_csr_wen);
//mtvec寄存器输出引线
wire [`E203_XLEN-1:0] mtvec_r;
//要写入mtvec寄存器的数据
wire [`E203_XLEN-1:0] mtvec_nxt = wbck_csr_dat;
//使用带有置位(load)和复位(reset)的dff实现mtvec
//                                        写入使能    写入的值    输出引线  时钟  复位
sirv_gnrl_dfflr #(`E203_XLEN) mtvec_dfflr (mtvec_ena, mtvec_nxt, mtvec_r, clk, rst_n);
//csr_mtvec用于将机器模式异常入口基地址寄存器的值传递给多路选择器，用于输出信号
wire [`E203_XLEN-1:0] csr_mtvec = mtvec_r;
`else//}{
  // THe vector table base is a configurable parameter, so we dont support writeable to it
//csr_mtvec用于将机器模式异常入口基地址寄存器的值传递给多路选择器，用于输出信号
wire [`E203_XLEN-1:0] csr_mtvec = `E203_MTVEC_TRAP_BASE;
`endif//}
//csr_mtvec_r用于将机器模式异常入口基地址寄存器的值输出
assign csr_mtvec_r = csr_mtvec;

//mscratch: 机器模式擦写寄存器(Machin e Scratch Register)
//0x340 MRW mscratch 
//是否选择mscratch寄存器 
wire sel_mscratch = (csr_idx == 12'h340);
//读取mscratch寄存器 
wire rd_mscratch = sel_mscratch & csr_rd_en;
`ifdef E203_SUPPORT_MSCRATCH //{
//写入mscratch寄存器 
wire wr_mscratch = sel_mscratch & csr_wr_en;
//写入mscratch寄存器的使能信号
wire mscratch_ena = (wr_mscratch & wbck_csr_wen);
//mscratch寄存器输出引线
wire [`E203_XLEN-1:0] mscratch_r;
//要写入mscratch寄存器的数据
wire [`E203_XLEN-1:0] mscratch_nxt = wbck_csr_dat;
//使用带有置位(load)和复位(reset)的dff实现mscratch寄存器
//                                              写入使能     写入的值       输出引线    时钟  复位
sirv_gnrl_dfflr #(`E203_XLEN) mscratch_dfflr (mscratch_ena, mscratch_nxt, mscratch_r, clk, rst_n);
//csr_mtvec用于将机器模式异常入口基地址寄存器的值传递给多路选择器，用于输出信号
wire [`E203_XLEN-1:0] csr_mscratch = mscratch_r;
`else//}{
//csr_mtvec用于将机器模式异常入口基地址寄存器的值传递给多路选择器，用于输出信号
wire [`E203_XLEN-1:0] csr_mscratch = `E203_XLEN'b0;
`endif//}

//mcycle: 周期计数器的低32位(Lower 32 bits of Cycle counter)
//mcycleh: 周期计数器的高32位(Upper 32 bits of Cycle counter)
//minstret: 退休指令计数器的低32位(Lower 32 bits of Instructions-retired counter)
//minstreth: 退休指令计数器的高32位(Upper 32 bits of Instructions-retired counter)
// 0xB00 MRW mcycle 
// 0xB02 MRW minstret 
// 0xB80 MRW mcycleh
// 0xB82 MRW minstreth
//是否选择相应的寄存器
wire sel_mcycle    = (csr_idx == 12'hB00);
wire sel_mcycleh   = (csr_idx == 12'hB80);
wire sel_minstret  = (csr_idx == 12'hB02);
wire sel_minstreth = (csr_idx == 12'hB82);

//mcounterstop: 自定义寄存器用于停止mtime、 mcycle、 mcycleh、 minstret 和 minstreth对应的计数器
// 0xBFF MRW counterstop 
      // This register is our self-defined register to stop
      // the cycle/time/instret counters to save dynamic powers
//是否选择mcounterstop寄存器
wire sel_counterstop = (csr_idx == 12'hBFF);// This address is not used by ISA
// 0xBFE MRW mcgstop 
      // This register is our self-defined register to disable the 
      // automaticall clock gating for CPU logics for debugging purpose
//mcgstop: machine clock gating stop
//是否选择mcgstop寄存器
wire sel_mcgstop = (csr_idx == 12'hBFE);// This address is not used by ISA
// 0xBFD MRW itcmnohold 
      // This register is our self-defined register to disble the 
      // ITCM SRAM output holdup feature, if set, then we assume
      // ITCM SRAM output cannot holdup last read value
wire sel_itcmnohold = (csr_idx == 12'hBFD);// This address is not used by ISA
// 0xBF0 MRW mdvnob2b 
      // This register is our self-defined register to disble the 
      // Mul/div back2back feature
wire sel_mdvnob2b = (csr_idx == 12'hBF0);// This address is not used by ISA

//是否读取相应寄存器的数据
wire rd_mcycle     = csr_rd_en & sel_mcycle   ;
wire rd_mcycleh    = csr_rd_en & sel_mcycleh  ;
wire rd_minstret   = csr_rd_en & sel_minstret ;
wire rd_minstreth  = csr_rd_en & sel_minstreth;

//是否读取相应寄存器的数据
wire rd_itcmnohold   = csr_rd_en & sel_itcmnohold;
wire rd_mdvnob2b   = csr_rd_en & sel_mdvnob2b;
wire rd_counterstop  = csr_rd_en & sel_counterstop;
wire rd_mcgstop       = csr_rd_en & sel_mcgstop;

`ifdef E203_SUPPORT_MCYCLE_MINSTRET //{
//是否写入相应寄存器的数据
wire wr_mcycle     = csr_wr_en & sel_mcycle   ;
wire wr_mcycleh    = csr_wr_en & sel_mcycleh  ;
wire wr_minstret   = csr_wr_en & sel_minstret ;
wire wr_minstreth  = csr_wr_en & sel_minstreth;

//是否写入相应寄存器的数据
wire wr_itcmnohold   = csr_wr_en & sel_itcmnohold ;
wire wr_mdvnob2b   = csr_wr_en & sel_mdvnob2b ;
wire wr_counterstop  = csr_wr_en & sel_counterstop;
wire wr_mcgstop       = csr_wr_en & sel_mcgstop     ;

//是否写入相应寄存器的数据
wire mcycle_wr_ena    = (wr_mcycle    & wbck_csr_wen);
wire mcycleh_wr_ena   = (wr_mcycleh   & wbck_csr_wen);
wire minstret_wr_ena  = (wr_minstret  & wbck_csr_wen);
wire minstreth_wr_ena = (wr_minstreth & wbck_csr_wen);

//是否写入相应寄存器的数据
wire itcmnohold_wr_ena  = (wr_itcmnohold  & wbck_csr_wen);
wire mdvnob2b_wr_ena  = (wr_mdvnob2b  & wbck_csr_wen);
wire counterstop_wr_ena = (wr_counterstop & wbck_csr_wen);
wire mcgstop_wr_ena      = (wr_mcgstop      & wbck_csr_wen);

//相应寄存器的输出引线
wire [`E203_XLEN-1:0] mcycle_r   ;
wire [`E203_XLEN-1:0] mcycleh_r  ;
wire [`E203_XLEN-1:0] minstret_r ;
wire [`E203_XLEN-1:0] minstreth_r;

//停止周期计数
wire cy_stop;
//停止指令退休
wire ir_stop;

wire stop_cycle_in_dbg = dbg_stopcycle & dbg_mode;
//相应的写入使能信号
wire mcycle_ena    = mcycle_wr_ena    | 
                     ((~cy_stop) & (~stop_cycle_in_dbg) & (1'b1));
wire mcycleh_ena   = mcycleh_wr_ena   | 
                     ((~cy_stop) & (~stop_cycle_in_dbg) & ((mcycle_r == (~(`E203_XLEN'b0)))));
wire minstret_ena  = minstret_wr_ena  |
                     ((~ir_stop) & (~stop_cycle_in_dbg) & (cmt_instret_ena));
wire minstreth_ena = minstreth_wr_ena |
                     ((~ir_stop) & (~stop_cycle_in_dbg) & ((cmt_instret_ena & (minstret_r == (~(`E203_XLEN'b0))))));

//相应的需要写入寄存器的数据
wire [`E203_XLEN-1:0] mcycle_nxt    = mcycle_wr_ena    ? wbck_csr_dat : (mcycle_r    + 1'b1);
wire [`E203_XLEN-1:0] mcycleh_nxt   = mcycleh_wr_ena   ? wbck_csr_dat : (mcycleh_r   + 1'b1);
wire [`E203_XLEN-1:0] minstret_nxt  = minstret_wr_ena  ? wbck_csr_dat : (minstret_r  + 1'b1);
wire [`E203_XLEN-1:0] minstreth_nxt = minstreth_wr_ena ? wbck_csr_dat : (minstreth_r + 1'b1);

//使用带有置位(load)和复位(reset)的dff实现相应寄存器
//                                        写入使能    写入的值    输出引线  时钟  复位
//We need to use the always-on clock for this counter
sirv_gnrl_dfflr #(`E203_XLEN) mcycle_dfflr (mcycle_ena, mcycle_nxt, mcycle_r   , clk_aon, rst_n);
sirv_gnrl_dfflr #(`E203_XLEN) mcycleh_dfflr (mcycleh_ena, mcycleh_nxt, mcycleh_r  , clk_aon, rst_n);
sirv_gnrl_dfflr #(`E203_XLEN) minstret_dfflr (minstret_ena, minstret_nxt, minstret_r , clk, rst_n);
sirv_gnrl_dfflr #(`E203_XLEN) minstreth_dfflr (minstreth_ena, minstreth_nxt, minstreth_r, clk, rst_n);

//mcounterstor输出数据引线
wire [`E203_XLEN-1:0] counterstop_r;
//mcounterstor写入使能信号
wire counterstop_ena = counterstop_wr_ena;
//写入mcounterstor的数据
wire [`E203_XLEN-1:0] counterstop_nxt = {29'b0,wbck_csr_dat[2:0]};// Only LSB 3bits are useful
//使用带有置位(load)和复位(reset)的dff实现mcounterstop寄存器
//                                               写入使能          写入的值          输出引线      时钟  复位
sirv_gnrl_dfflr #(`E203_XLEN) counterstop_dfflr (counterstop_ena, counterstop_nxt, counterstop_r, clk, rst_n);

//相应寄存器的数据输出
wire [`E203_XLEN-1:0] csr_mcycle    = mcycle_r;
wire [`E203_XLEN-1:0] csr_mcycleh   = mcycleh_r;
wire [`E203_XLEN-1:0] csr_minstret  = minstret_r;
wire [`E203_XLEN-1:0] csr_minstreth = minstreth_r;
wire [`E203_XLEN-1:0] csr_counterstop = counterstop_r;
`else//}{
//相应寄存器的数据输出，未定义则全部输出0
wire [`E203_XLEN-1:0] csr_mcycle    = `E203_XLEN'b0;
wire [`E203_XLEN-1:0] csr_mcycleh   = `E203_XLEN'b0;
wire [`E203_XLEN-1:0] csr_minstret  = `E203_XLEN'b0;
wire [`E203_XLEN-1:0] csr_minstreth = `E203_XLEN'b0;
wire [`E203_XLEN-1:0] csr_counterstop = `E203_XLEN'b0;
`endif//}

//itcmnohold寄存器输出引线
wire [`E203_XLEN-1:0] itcmnohold_r;
//itcmnohold寄存器写入使能
wire itcmnohold_ena = itcmnohold_wr_ena;
//往itcmnohold寄存器写入的数据
wire [`E203_XLEN-1:0] itcmnohold_nxt = {31'b0,wbck_csr_dat[0]};// Only LSB 1bits are useful
//使用带有置位(load)和复位(reset)的dff实现itcmnohold寄存器
//                                               写入使能          写入的值          输出引线      时钟  复位
sirv_gnrl_dfflr #(`E203_XLEN) itcmnohold_dfflr (itcmnohold_ena, itcmnohold_nxt, itcmnohold_r, clk, rst_n);

wire [`E203_XLEN-1:0] csr_itcmnohold  = itcmnohold_r;

//mdvnob2b寄存器输出引线
wire [`E203_XLEN-1:0] mdvnob2b_r;
//mdvnob2b寄存器写入使能
wire mdvnob2b_ena = mdvnob2b_wr_ena;
//往mdvnob2b寄存器写入的数据
wire [`E203_XLEN-1:0] mdvnob2b_nxt = {31'b0,wbck_csr_dat[0]};// Only LSB 1bits are useful
//使用带有置位(load)和复位(reset)的dff实现mdvnob2b寄存器
sirv_gnrl_dfflr #(`E203_XLEN) mdvnob2b_dfflr (mdvnob2b_ena, mdvnob2b_nxt, mdvnob2b_r, clk, rst_n);

//输出mdvnob2b寄存器的引线
wire [`E203_XLEN-1:0] csr_mdvnob2b  = mdvnob2b_r;

assign cy_stop = counterstop_r[0];// Stop CYCLE   counter
assign tm_stop = counterstop_r[1];// Stop TIME    counter
assign ir_stop = counterstop_r[2];// Stop INSTRET counter

assign itcm_nohold = itcmnohold_r[0];// ITCM no-hold up feature
assign mdv_nob2b = mdvnob2b_r[0];// Mul/Div no back2back feature


//mcgstop寄存器输出引线
wire [`E203_XLEN-1:0] mcgstop_r;
//mcgstop寄存器写入使能
wire mcgstop_ena = mcgstop_wr_ena;
//往mcgstop寄存器写入的数据
wire [`E203_XLEN-1:0] mcgstop_nxt = {30'b0,wbck_csr_dat[1:0]};// Only LSB 2bits are useful
//使用带有置位(load)和复位(reset)的dff实现mcgstop寄存器
sirv_gnrl_dfflr #(`E203_XLEN) mcgstop_dfflr (mcgstop_ena, mcgstop_nxt, mcgstop_r, clk, rst_n);
//输出mcgstop寄存器的引线
wire [`E203_XLEN-1:0] csr_mcgstop = mcgstop_r;
assign core_cgstop = mcgstop_r[0];// Stop Core clock gating
assign tcm_cgstop = mcgstop_r[1];// Stop TCM  clock gating


//`ifdef E203_SUPPORT_CYCLE //{
////0xC00 URO cycle 
////0xC80 URO cycleh
//wire sel_cycle  = (csr_idx == 12'hc00);
//wire sel_cycleh = (csr_idx == 12'hc80);
//wire rd_cycle = sel_cycle & csr_rd_en;
//wire wr_cycle = sel_cycle & csr_wr_en;
//wire cycle_ena = (wr_cycle & wbck_csr_wen);
//wire rd_cycleh = sel_cycleh & csr_rd_en;
//wire wr_cycleh = sel_cycleh & csr_wr_en;
//wire cycleh_ena = (wr_cycleh & wbck_csr_wen);
//wire [`E203_XLEN-1:0] cycle_r;
//wire [`E203_XLEN-1:0] cycleh_r;
//wire [`E203_XLEN-1:0] cycle_nxt = wbck_csr_dat;
//wire [`E203_XLEN-1:0] cycleh_nxt = wbck_csr_dat;
//sirv_gnrl_dfflr #(`E203_XLEN) cycle_dfflr (cycle_ena, cycle_nxt, cycle_r, clk, rst_n);
//sirv_gnrl_dfflr #(`E203_XLEN) cycleh_dfflr(cycleh_ena,cycleh_nxt,cycleh_r,clk, rst_n);
//wire [`E203_XLEN-1:0] csr_cycle  = cycle_r;
//wire [`E203_XLEN-1:0] csr_cycleh = cycleh_r;
//`else//}{
//wire [`E203_XLEN-1:0] csr_cycle = `E203_XLEN'b0;
//wire [`E203_XLEN-1:0] csr_cycleh = `E203_XLEN'b0;
//`endif//}

//机器模式异常 PC 寄存器 mepc ( Machine Exception Program Counter )
//出现中断时，中断返回地址mepc的值被更新为下一条尚未执行的指令的地址。
//0x041 URW uepc User exception program counter.
//  We dont support user trap, so no uepc needed
//0x341 MRW mepc Machine exception program counter.
wire sel_mepc = (csr_idx == 12'h341);
wire rd_mepc = sel_mepc & csr_rd_en;
wire wr_mepc = sel_mepc & csr_wr_en;
wire epc_ena = (wr_mepc & wbck_csr_wen) | cmt_epc_ena;
wire [`E203_PC_SIZE-1:0] epc_r;
wire [`E203_PC_SIZE-1:0] epc_nxt;
assign epc_nxt[`E203_PC_SIZE-1:1] = cmt_epc_ena ? cmt_epc[`E203_PC_SIZE-1:1] : wbck_csr_dat[`E203_PC_SIZE-1:1];
assign epc_nxt[0] = 1'b0;// Must not hold PC which will generate the misalign exception according to ISA
sirv_gnrl_dfflr #(`E203_PC_SIZE) epc_dfflr (epc_ena, epc_nxt, epc_r, clk, rst_n);
wire [`E203_XLEN-1:0] csr_mepc;
wire dummy_0;
assign {dummy_0,csr_mepc} = {{`E203_XLEN+1-`E203_PC_SIZE{1'b0}},epc_r};
assign csr_epc_r = csr_mepc;

//机器模式异常原因寄存器 mcause (Machine Cause Register )
//0x042 URW ucause User trap cause.
//  We dont support user trap, so no ucause needed
//0x342 MRW mcause Machine trap cause.
//是否选择mcause寄存器
wire sel_mcause = (csr_idx == 12'h342);
//是否读取mcause寄存器中的数据
wire rd_mcause = sel_mcause & csr_rd_en;
//是否向mcause寄存器中写入数据
wire wr_mcause = sel_mcause & csr_wr_en;
//mcause寄存器写入使能信号
wire cause_ena = (wr_mcause & wbck_csr_wen) | cmt_cause_ena;
//mcause寄存器输出引线
wire [`E203_XLEN-1:0] cause_r;
//向mcause寄存器中写入的数据
wire [`E203_XLEN-1:0] cause_nxt;
//向mcause寄存器中写入的数据
assign cause_nxt[31]  = cmt_cause_ena ? cmt_cause[31] : wbck_csr_dat[31];
assign cause_nxt[30:4] = 27'b0;
assign cause_nxt[3:0] = cmt_cause_ena ? cmt_cause[3:0] : wbck_csr_dat[3:0];
//带有置位和复位的dff实现的mcause寄存器
sirv_gnrl_dfflr #(`E203_XLEN) cause_dfflr (cause_ena, cause_nxt, cause_r, clk, rst_n);
//mcause寄存器输出引线
wire [`E203_XLEN-1:0] csr_mcause = cause_r;


//机器模式异常值寄存器 mtval (Machine Trap Value Register ），以反映引起当前异常的存储器访问地址或者指令编码。
//mtval 寄存器又名 mbadaddr 寄存器，在某些早期版本的 阳SC-V 编译器中仅识别mbadaddr名称，详见书P245
//0x043 URW ubadaddr User bad address.
//  We dont support user trap, so no ubadaddr needed
//0x343 MRW mbadaddr Machine bad address.
wire sel_mbadaddr = (csr_idx == 12'h343);
wire rd_mbadaddr = sel_mbadaddr & csr_rd_en;
wire wr_mbadaddr = sel_mbadaddr & csr_wr_en;
wire cmt_trap_badaddr_ena = cmt_badaddr_ena;
wire badaddr_ena = (wr_mbadaddr & wbck_csr_wen) | cmt_trap_badaddr_ena;
wire [`E203_ADDR_SIZE-1:0] badaddr_r;
wire [`E203_ADDR_SIZE-1:0] badaddr_nxt;
assign badaddr_nxt = cmt_trap_badaddr_ena ? cmt_badaddr : wbck_csr_dat[`E203_ADDR_SIZE-1:0];
sirv_gnrl_dfflr #(`E203_ADDR_SIZE) badaddr_dfflr (badaddr_ena, badaddr_nxt, badaddr_r, clk, rst_n);
wire [`E203_XLEN-1:0] csr_mbadaddr;
wire dummy_1;
assign {dummy_1,csr_mbadaddr} = {{`E203_XLEN+1-`E203_ADDR_SIZE{1'b0}},badaddr_r};

// We dont support the delegation scheme, so no need to implement
//   delegete registers


//MISA: 机器模式指令集架构寄存器（ Machine ISA Register)
//0x301 MRW misa ISA and extensions
wire sel_misa = (csr_idx == 12'h301);
wire rd_misa = sel_misa & csr_rd_en;
// Only implemented the M mode, IMC or EMC
wire [`E203_XLEN-1:0] csr_misa = {
    2'b1
   ,4'b0 //WIRI
   ,1'b0 //              25 Z Reserved
   ,1'b0 //              24 Y Reserved
   ,1'b0 //              23 X Non-standard extensions present
   ,1'b0 //              22 W Reserved
   ,1'b0 //              21 V Tentatively reserved for Vector extension 20 U User mode implemented
   ,1'b0 //              20 U User mode implemented
   ,1'b0 //              19 T Tentatively reserved for Transactional Memory extension
   ,1'b0 //              18 S Supervisor mode implemented
   ,1'b0 //              17 R Reserved
   ,1'b0 //              16 Q Quad-precision floating-point extension
   ,1'b0 //              15 P Tentatively reserved for Packed-SIMD extension
   ,1'b0 //              14 O Reserved
   ,1'b0 //              13 N User-level interrupts supported
   ,1'b1 // 12 M Integer Multiply/Divide extension
   ,1'b0 //              11 L Tentatively reserved for Decimal Floating-Point extension
   ,1'b0 //              10 K Reserved
   ,1'b0 //              9 J Reserved
   `ifdef E203_RFREG_NUM_IS_32
   ,1'b1 // 8 I RV32I/64I/128I base ISA
   `else
   ,1'b0
   `endif
   ,1'b0 //              7 H Hypervisor mode implemented
   ,1'b0 //              6 G Additional standard extensions present
  `ifndef E203_HAS_FPU//{
   ,1'b0 //              5 F Single-precision floating-point extension
  `endif//
   `ifdef E203_RFREG_NUM_IS_32
   ,1'b0 //              4 E RV32E base ISA
   `else
   ,1'b1 //              
   `endif
  `ifndef E203_HAS_FPU//{
   ,1'b0 //              3 D Double-precision floating-point extension
  `endif//
   ,1'b1 // 2 C Compressed extension
   ,1'b0 //              1 B Tentatively reserved for Bit operations extension
  `ifdef E203_SUPPORT_AMO//{
   ,1'b1 //              0 A Atomic extension
  `endif//E203_SUPPORT_AMO}
  `ifndef E203_SUPPORT_AMO//{
   ,1'b0 //              0 A Atomic extension
  `endif//}
                           };

//mvendorid: 机器模式供应商编号寄存器（Machine Vendor ID Register)
//marchid: 机器模式架构编号寄存器 (Machine Architecture ID Register)
//mimpid: 机器模式硬件实现编号寄存器 (Machine Implementation ID Register)
//mhartid: Hart编号寄存器(Hart ID Register)
//Machine Information Registers
//0xF11 MRO mvendorid Vendor ID.
//0xF12 MRO marchid Architecture ID.
//0xF13 MRO mimpid Implementation ID.
//0xF14 MRO mhartid Hardware thread ID.
wire [`E203_XLEN-1:0] csr_mvendorid = `E203_XLEN'h`E203_MVENDORID;
wire [`E203_XLEN-1:0] csr_marchid   = `E203_XLEN'h`E203_MARCHID  ;
wire [`E203_XLEN-1:0] csr_mimpid    = `E203_XLEN'h`E203_MIMPID   ;
wire [`E203_XLEN-1:0] csr_mhartid   = {{`E203_XLEN-`E203_HART_ID_W{1'b0}},core_mhartid};
wire rd_mvendorid = csr_rd_en & (csr_idx == 12'hF11);
wire rd_marchid   = csr_rd_en & (csr_idx == 12'hF12);
wire rd_mimpid    = csr_rd_en & (csr_idx == 12'hF13);
wire rd_mhartid   = csr_rd_en & (csr_idx == 12'hF14);

//0x7b0 Debug Control and Status
//0x7b1 Debug PC
//0x7b2 Debug Scratch Register
//0x7a0 Trigger selection register
wire sel_dcsr     = (csr_idx == 12'h7b0);
wire sel_dpc      = (csr_idx == 12'h7b1);
wire sel_dscratch = (csr_idx == 12'h7b2);

wire rd_dcsr     = dbg_mode & csr_rd_en & sel_dcsr    ;
wire rd_dpc      = dbg_mode & csr_rd_en & sel_dpc     ;
wire rd_dscratch = dbg_mode & csr_rd_en & sel_dscratch;


assign wr_dcsr_ena     = dbg_mode & csr_wr_en & sel_dcsr    ;
assign wr_dpc_ena      = dbg_mode & csr_wr_en & sel_dpc     ;
assign wr_dscratch_ena = dbg_mode & csr_wr_en & sel_dscratch;


assign wr_csr_nxt     = wbck_csr_dat;


wire [`E203_XLEN-1:0] csr_dcsr     = dcsr_r    ;
`ifdef E203_PC_SIZE_IS_16
wire [`E203_XLEN-1:0] csr_dpc      = {{`E203_XLEN-`E203_PC_SIZE{1'b0}},dpc_r};
`endif
`ifdef E203_PC_SIZE_IS_24
wire [`E203_XLEN-1:0] csr_dpc      = {{`E203_XLEN-`E203_PC_SIZE{1'b0}},dpc_r};
`endif
`ifdef E203_PC_SIZE_IS_32
wire [`E203_XLEN-1:0] csr_dpc      = dpc_r     ;
`endif
wire [`E203_XLEN-1:0] csr_dscratch = dscratch_r;

assign csr_dpc_r = dpc_r;

/////////////////////////////////////////////////////////////////////
//  Generate the Read path
  //Currently we only support the M mode to simplify the implementation and 
  //      reduce the gatecount because we are a privite core
assign u_mode = 1'b0;
assign s_mode = 1'b0;
assign h_mode = 1'b0;
//E200只支持机器模式
assign m_mode = 1'b1;
//多路选择器选择输出数据
assign read_csr_dat = `E203_XLEN'b0 
               //| ({`E203_XLEN{rd_ustatus  }} & csr_ustatus  )
               | ({`E203_XLEN{rd_mstatus  }} & csr_mstatus  )
               | ({`E203_XLEN{rd_mie      }} & csr_mie      )
               | ({`E203_XLEN{rd_mtvec    }} & csr_mtvec    )
               | ({`E203_XLEN{rd_mepc     }} & csr_mepc     )
               | ({`E203_XLEN{rd_mscratch }} & csr_mscratch )
               | ({`E203_XLEN{rd_mcause   }} & csr_mcause   )
               | ({`E203_XLEN{rd_mbadaddr }} & csr_mbadaddr )
               | ({`E203_XLEN{rd_mip      }} & csr_mip      )
               | ({`E203_XLEN{rd_misa     }} & csr_misa      )
               | ({`E203_XLEN{rd_mvendorid}} & csr_mvendorid)
               | ({`E203_XLEN{rd_marchid  }} & csr_marchid  )
               | ({`E203_XLEN{rd_mimpid   }} & csr_mimpid   )
               | ({`E203_XLEN{rd_mhartid  }} & csr_mhartid  )
               | ({`E203_XLEN{rd_mcycle   }} & csr_mcycle   )
               | ({`E203_XLEN{rd_mcycleh  }} & csr_mcycleh  )
               | ({`E203_XLEN{rd_minstret }} & csr_minstret )
               | ({`E203_XLEN{rd_minstreth}} & csr_minstreth)
               | ({`E203_XLEN{rd_counterstop}} & csr_counterstop)// Self-defined
               | ({`E203_XLEN{rd_mcgstop}} & csr_mcgstop)// Self-defined
               | ({`E203_XLEN{rd_itcmnohold}} & csr_itcmnohold)// Self-defined
               | ({`E203_XLEN{rd_mdvnob2b}} & csr_mdvnob2b)// Self-defined
               | ({`E203_XLEN{rd_dcsr     }} & csr_dcsr    )
               | ({`E203_XLEN{rd_dpc      }} & csr_dpc     )
               | ({`E203_XLEN{rd_dscratch }} & csr_dscratch)
               ;


endmodule

