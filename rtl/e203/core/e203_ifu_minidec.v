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
// Designer   : Bob Hu
//
// Description:
//  The mini-decode module to decode the instruction in IFU 
//
// ====================================================================
`include "e203_defines.v"

module e203_ifu_minidec(

  //////////////////////////////////////////////////////////////
  // The IR stage to Decoder
  //传入的指令
  input  [`E203_INSTR_SIZE-1:0] instr,
  
  //////////////////////////////////////////////////////////////
  // The Decoded Info-Bus


  //源操作数1使能信号
  output dec_rs1en,
  //源操作数2使能信号
  output dec_rs2en,
  //源操作数1序号
  output [`E203_RFIDX_WIDTH-1:0] dec_rs1idx,
  //源操作数2序号
  output [`E203_RFIDX_WIDTH-1:0] dec_rs2idx,

  //mulhsu 指令将操作数寄存器 rsl 与 rs2 中的 32 位整数相乘，其中 rsl 和 rs2 中的值分别被当作有符号数和无符号数，将结果的高 32 位写回寄存器 rd 中。
  output dec_mulhsu,
  //指令将操作数寄存器 rsl 与 rs2 中的 32 位整数相乘，将结果的低 32 位写回寄存器 rd 中 
  output dec_mul   ,
  //除法
  output dec_div   ,
  //余数
  output dec_rem   ,
  //无符号除法
  output dec_divu  ,
  output dec_remu  ,

  //是否为32位指令
  output dec_rv32,
  //是否为跳转指令
  output dec_bjp,
  //是否为立即数无条件跳转指令
  output dec_jal,
  //是否为寄存器无条件跳转指令
  output dec_jalr,
  //是否为条件跳转指令
  output dec_bxx,
  //寄存器无条件跳转指令的寄存器序号
  output [`E203_RFIDX_WIDTH-1:0] dec_jalr_rs1idx,
  //跳转的立即数
  output [`E203_XLEN-1:0] dec_bjp_imm 

  );

  e203_exu_decode u_e203_exu_decode(
  //输入指令
  .i_instr(instr),
  //不需要的输入的信息置零
  .i_pc(`E203_PC_SIZE'b0),
  .i_prdt_taken(1'b0), 
  .i_muldiv_b2b(1'b0), 

  .i_misalgn (1'b0),
  .i_buserr  (1'b0),

  .dbg_mode  (1'b0),

  //不需要的输出的信息悬空
  .dec_misalgn(),
  .dec_buserr(),
  .dec_ilegl(),

  .dec_rs1x0(),
  .dec_rs2x0(),
  //rs1使能信号
  .dec_rs1en(dec_rs1en),
  //rs2使能信号
  .dec_rs2en(dec_rs2en),
  .dec_rdwen(),
  //rs1序号
  .dec_rs1idx(dec_rs1idx),
  //rs2序号
  .dec_rs2idx(dec_rs2idx),
  //不需要的输出的信息悬空
  .dec_rdidx(),
  .dec_info(),  
  .dec_imm(),
  .dec_pc(),

  //判断操作的类型
  .dec_mulhsu(dec_mulhsu),
  .dec_mul   (dec_mul   ),
  .dec_div   (dec_div   ),
  .dec_rem   (dec_rem   ),
  .dec_divu  (dec_divu  ),
  .dec_remu  (dec_remu  ),

  //是否是32位指令
  .dec_rv32(dec_rv32),
  //是否是跳转指令
  .dec_bjp (dec_bjp ),
  //是否为立即数无条件跳转指令
  .dec_jal (dec_jal ),
  //是否为寄存器无条件跳转指令
  .dec_jalr(dec_jalr),
  //是否为条件跳转指令
  .dec_bxx (dec_bxx ),

  //寄存器无条件跳转指令的寄存器序号
  .dec_jalr_rs1idx(dec_jalr_rs1idx),
  //跳转的立即数
  .dec_bjp_imm    (dec_bjp_imm    ),
  .is_rd_32_x0 ()
  );


endmodule
