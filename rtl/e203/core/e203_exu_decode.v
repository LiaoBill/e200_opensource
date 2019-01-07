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
//  The decode module to decode the instruction details
//
// ====================================================================
`include "e203_defines.v"

module e203_exu_decode(

  //////////////////////////////////////////////////////////////
  // The IR stage to Decoder
  //输入指令
  input  [`E203_INSTR_SIZE-1:0] i_instr,
  //输入的PC
  input  [`E203_PC_SIZE-1:0] i_pc,
  //ifu预测的是否跳转
  input  i_prdt_taken,
  //读取的指令是否是4bytes对齐的
  input  i_misalgn,              // The fetch misalign
  input  i_buserr,               // The fetch bus error
  input  i_muldiv_b2b,           // The back2back case for mul/div

  input  dbg_mode,
  //////////////////////////////////////////////////////////////
  // The Decoded Info-Bus

  //rs1是不是x0
  output dec_rs1x0,
  //rs2是不是x0
  output dec_rs2x0,
  //rs1使能
  output dec_rs1en,
  //rs2使能
  output dec_rs2en,
  //rd写使能
  output dec_rdwen,
  //rs1序号
  output [`E203_RFIDX_WIDTH-1:0] dec_rs1idx,
  //rs2序号
  output [`E203_RFIDX_WIDTH-1:0] dec_rs2idx,
  //rd序号
  output [`E203_RFIDX_WIDTH-1:0] dec_rdidx,
  //译码信息输出
  output [`E203_DECINFO_WIDTH-1:0] dec_info,
  //译码得到的立即数
  output [`E203_XLEN-1:0] dec_imm,
  //译码后更新的PC
  output [`E203_PC_SIZE-1:0] dec_pc,
  //译码未对齐
  output dec_misalgn,
  //译码总线错误
  output dec_buserr,
  //译码错误
  output dec_ilegl,

  //mulhsu 指令将操作数寄存器 rsl 与 rs2 中的 32 位整数相乘，其中 rsl 和 rs2 中的值分别被当作有符号数和无符号数，将结果的高 32 位写回寄存器 rd 中。
  output dec_mulhsu,
  //乘法
  output dec_mul   ,
  //除法
  output dec_div   ,
  //求余数
  output dec_rem   ,
  //无符号除法
  output dec_divu  ,
  //无符号求余数
  output dec_remu  ,

  //是否为32位指令
  output dec_rv32,
  //跳转指令还是普通指令
  output dec_bjp,
  //是否为绝对跳转
  output dec_jal,
  //是否为绝对跳转
  output dec_jalr,
  //是否为条件跳转指令
  output dec_bxx,

  //jalr的寄存器地址
  output [`E203_RFIDX_WIDTH-1:0] dec_jalr_rs1idx,
  //跳转指令的立即数
  output [`E203_XLEN-1:0] dec_bjp_imm,

  // --------- add/modify/delete code ---------
  output is_rd_32_x0
  );

// --------- add/modify/delete code ---------
assign is_rd_32_x0 = rv32_rd_x0;


  //32位指令使用全部32位输入
  wire [32-1:0] rv32_instr = i_instr;
  //16位指令使用32位输入中的低16位
  wire [16-1:0] rv16_instr = i_instr[15:0];

  //获取opcode
  wire [6:0]  opcode = rv32_instr[6:0];

  //判断指令长度，参加书P98
  wire opcode_1_0_00  = (opcode[1:0] == 2'b00);
  wire opcode_1_0_01  = (opcode[1:0] == 2'b01);
  wire opcode_1_0_10  = (opcode[1:0] == 2'b10);
  wire opcode_1_0_11  = (opcode[1:0] == 2'b11);

  //是否为32位指令  xxxxxbbb11, bbb != 111   bbb: i_instr[4:2]  11:opcode_1_0_11
  wire rv32 = (~(i_instr[4:2] == 3'b111)) & opcode_1_0_11;

  //解析32位指令，详见riscv-spec-v2.2.pdf P11
  //目标寄存器
  wire [4:0]  rv32_rd     = rv32_instr[11:7];
  //长度为3的func3域， R-type， I-type， S-type有这个域
  wire [2:0]  rv32_func3  = rv32_instr[14:12];
  //源操作数1
  wire [4:0]  rv32_rs1    = rv32_instr[19:15];
  //源操作数2
  wire [4:0]  rv32_rs2    = rv32_instr[24:20];
  //长度为7的func7域， R-type有这个域
  wire [6:0]  rv32_func7  = rv32_instr[31:25];

  //解析16位指令，详见riscv-spec-v2.2.pdf P70
  //目标寄存器
  wire [4:0]  rv16_rd     = rv32_rd;
  //源操作数1
  wire [4:0]  rv16_rs1    = rv16_rd;
  //源操作数2
  wire [4:0]  rv16_rs2    = rv32_instr[6:2];

  //解析16位指令，详见riscv-spec-v2.2.pdf P70
  //rss1' rdd是CL(compressed load)或CS(compressed store)的rs1'和rd'
  wire [4:0]  rv16_rdd    = {2'b01,rv32_instr[4:2]};
  wire [4:0]  rv16_rss1   = {2'b01,rv32_instr[9:7]};
  //rs2'和rd'是同一个寄存器
  wire [4:0]  rv16_rss2   = rv16_rdd;

  //长度为3的func3域，见riscv-spec-v2.2.pdf P70
  wire [2:0]  rv16_func3  = rv32_instr[15:13];


  // We generate the signals and reused them as much as possible to save gatecounts
  //opcode_a_b_xxx 意思是opcode[a:b] == xxx
  wire opcode_4_2_000 = (opcode[4:2] == 3'b000);
  wire opcode_4_2_001 = (opcode[4:2] == 3'b001);
  wire opcode_4_2_010 = (opcode[4:2] == 3'b010);
  wire opcode_4_2_011 = (opcode[4:2] == 3'b011);
  wire opcode_4_2_100 = (opcode[4:2] == 3'b100);
  wire opcode_4_2_101 = (opcode[4:2] == 3'b101);
  wire opcode_4_2_110 = (opcode[4:2] == 3'b110);
  wire opcode_4_2_111 = (opcode[4:2] == 3'b111);
  wire opcode_6_5_00  = (opcode[6:5] == 2'b00);
  wire opcode_6_5_01  = (opcode[6:5] == 2'b01);
  wire opcode_6_5_10  = (opcode[6:5] == 2'b10);
  wire opcode_6_5_11  = (opcode[6:5] == 2'b11);


  //rv32_func3_xxx 意思是 32位指令的func3域 == xxx
  wire rv32_func3_000 = (rv32_func3 == 3'b000);
  wire rv32_func3_001 = (rv32_func3 == 3'b001);
  wire rv32_func3_010 = (rv32_func3 == 3'b010);
  wire rv32_func3_011 = (rv32_func3 == 3'b011);
  wire rv32_func3_100 = (rv32_func3 == 3'b100);
  wire rv32_func3_101 = (rv32_func3 == 3'b101);
  wire rv32_func3_110 = (rv32_func3 == 3'b110);
  wire rv32_func3_111 = (rv32_func3 == 3'b111);

  //rv16_func3_xxx 意思是 16位指令的func3域 == xxx
  wire rv16_func3_000 = (rv16_func3 == 3'b000);
  wire rv16_func3_001 = (rv16_func3 == 3'b001);
  wire rv16_func3_010 = (rv16_func3 == 3'b010);
  wire rv16_func3_011 = (rv16_func3 == 3'b011);
  wire rv16_func3_100 = (rv16_func3 == 3'b100);
  wire rv16_func3_101 = (rv16_func3 == 3'b101);
  wire rv16_func3_110 = (rv16_func3 == 3'b110);
  wire rv16_func3_111 = (rv16_func3 == 3'b111);

  //rv32_func7_xxxxxxx 意思是 32位指令的func7域 == xxxxxxx
  wire rv32_func7_0000000 = (rv32_func7 == 7'b0000000);
  wire rv32_func7_0100000 = (rv32_func7 == 7'b0100000);
  wire rv32_func7_0000001 = (rv32_func7 == 7'b0000001);
  wire rv32_func7_0000101 = (rv32_func7 == 7'b0000101);
  wire rv32_func7_0001001 = (rv32_func7 == 7'b0001001);
  wire rv32_func7_0001101 = (rv32_func7 == 7'b0001101);
  wire rv32_func7_0010101 = (rv32_func7 == 7'b0010101);
  wire rv32_func7_0100001 = (rv32_func7 == 7'b0100001);
  wire rv32_func7_0010001 = (rv32_func7 == 7'b0010001);
  wire rv32_func7_0101101 = (rv32_func7 == 7'b0101101);
  wire rv32_func7_1111111 = (rv32_func7 == 7'b1111111);
  wire rv32_func7_0000100 = (rv32_func7 == 7'b0000100);
  wire rv32_func7_0001000 = (rv32_func7 == 7'b0001000);
  wire rv32_func7_0001100 = (rv32_func7 == 7'b0001100);
  wire rv32_func7_0101100 = (rv32_func7 == 7'b0101100);
  wire rv32_func7_0010000 = (rv32_func7 == 7'b0010000);
  wire rv32_func7_0010100 = (rv32_func7 == 7'b0010100);
  wire rv32_func7_1100000 = (rv32_func7 == 7'b1100000);
  wire rv32_func7_1110000 = (rv32_func7 == 7'b1110000);
  wire rv32_func7_1010000 = (rv32_func7 == 7'b1010000);
  wire rv32_func7_1101000 = (rv32_func7 == 7'b1101000);
  wire rv32_func7_1111000 = (rv32_func7 == 7'b1111000);
  wire rv32_func7_1010001 = (rv32_func7 == 7'b1010001);
  wire rv32_func7_1110001 = (rv32_func7 == 7'b1110001);
  wire rv32_func7_1100001 = (rv32_func7 == 7'b1100001);
  wire rv32_func7_1101001 = (rv32_func7 == 7'b1101001);

  //32位指令的rs1是x0
  wire rv32_rs1_x0 = (rv32_rs1 == 5'b00000);
  //32位指令的rs2是x0
  wire rv32_rs2_x0 = (rv32_rs2 == 5'b00000);
  //32位指令的rs2是x1
  wire rv32_rs2_x1 = (rv32_rs2 == 5'b00001);
  //32位指令的rd是x0
  wire rv32_rd_x0  = (rv32_rd  == 5'b00000);
  //32位指令的rs2是x2
  wire rv32_rd_x2  = (rv32_rd  == 5'b00010);

  //16位指令的rs1是x0
  wire rv16_rs1_x0 = (rv16_rs1 == 5'b00000);
  //16位指令的rs2是x0
  wire rv16_rs2_x0 = (rv16_rs2 == 5'b00000);
  //16位指令的rd是x0
  wire rv16_rd_x0  = (rv16_rd  == 5'b00000);
  //16位指令的rd1是x2
  wire rv16_rd_x2  = (rv16_rd  == 5'b00010);

  //32位指令的rs1是x31
  wire rv32_rs1_x31 = (rv32_rs1 == 5'b11111);
  //32位指令的rs2是x31
  wire rv32_rs2_x31 = (rv32_rs2 == 5'b11111);
  //32位指令的rd是x31
  wire rv32_rd_x31  = (rv32_rd  == 5'b11111);

  //如何解析指令参见书P278表16-1
  //32位load指令
  wire rv32_load     = opcode_6_5_00 & opcode_4_2_000 & opcode_1_0_11;
  //32位store指令
  wire rv32_store    = opcode_6_5_01 & opcode_4_2_000 & opcode_1_0_11;
  //32位madd指令，
  wire rv32_madd     = opcode_6_5_10 & opcode_4_2_000 & opcode_1_0_11;
  //条件跳转指令
  wire rv32_branch   = opcode_6_5_11 & opcode_4_2_000 & opcode_1_0_11;

  //浮点指令
  wire rv32_load_fp  = opcode_6_5_00 & opcode_4_2_001 & opcode_1_0_11;
  wire rv32_store_fp = opcode_6_5_01 & opcode_4_2_001 & opcode_1_0_11;
  wire rv32_msub     = opcode_6_5_10 & opcode_4_2_001 & opcode_1_0_11;
  //绝对跳转指令
  wire rv32_jalr     = opcode_6_5_11 & opcode_4_2_001 & opcode_1_0_11;

  //用户自定义指令0
  wire rv32_custom0  = opcode_6_5_00 & opcode_4_2_010 & opcode_1_0_11;
  //用户自定义指令1
  wire rv32_custom1  = opcode_6_5_01 & opcode_4_2_010 & opcode_1_0_11;
  //浮点减法
  wire rv32_nmsub    = opcode_6_5_10 & opcode_4_2_010 & opcode_1_0_11;
  //保留
  wire rv32_resved0  = opcode_6_5_11 & opcode_4_2_010 & opcode_1_0_11;

  wire rv32_miscmem  = opcode_6_5_00 & opcode_4_2_011 & opcode_1_0_11;
  //原子内存操作
  `ifdef E203_SUPPORT_AMO//{
  //支持原子操作
  wire rv32_amo      = opcode_6_5_01 & opcode_4_2_011 & opcode_1_0_11;
  `endif//E203_SUPPORT_AMO}
  `ifndef E203_SUPPORT_AMO//{
  //不支持原子操作
  wire rv32_amo      = 1'b0;
  `endif//}
  //nmadd指令
  wire rv32_nmadd    = opcode_6_5_10 & opcode_4_2_011 & opcode_1_0_11;
  //立即数绝对跳转
  wire rv32_jal      = opcode_6_5_11 & opcode_4_2_011 & opcode_1_0_11;

  //带有立即数的指令， 表16-1中的OP-IMM
  wire rv32_op_imm   = opcode_6_5_00 & opcode_4_2_100 & opcode_1_0_11;
  //普通指令，表16-1中的OP
  wire rv32_op       = opcode_6_5_01 & opcode_4_2_100 & opcode_1_0_11;
  //浮点数指令，表16-1中的OP-FP
  wire rv32_op_fp    = opcode_6_5_10 & opcode_4_2_100 & opcode_1_0_11;
  //系统指令，表16-1中的System
  wire rv32_system   = opcode_6_5_11 & opcode_4_2_100 & opcode_1_0_11;

  //表16-1中的AUIPC，以下所有指令解析均可以参考P278表16-1
  wire rv32_auipc    = opcode_6_5_00 & opcode_4_2_101 & opcode_1_0_11;
  wire rv32_lui      = opcode_6_5_01 & opcode_4_2_101 & opcode_1_0_11;
  wire rv32_resved1  = opcode_6_5_10 & opcode_4_2_101 & opcode_1_0_11;
  wire rv32_resved2  = opcode_6_5_11 & opcode_4_2_101 & opcode_1_0_11;

  wire rv32_op_imm_32= opcode_6_5_00 & opcode_4_2_110 & opcode_1_0_11;
  wire rv32_op_32    = opcode_6_5_01 & opcode_4_2_110 & opcode_1_0_11;
  wire rv32_custom2  = opcode_6_5_10 & opcode_4_2_110 & opcode_1_0_11;
  wire rv32_custom3  = opcode_6_5_11 & opcode_4_2_110 & opcode_1_0_11;

  //解析16位指令，以下所有指令解析均可以参考P278表16-2
  wire rv16_addi4spn     = opcode_1_0_00 & rv16_func3_000;//
  wire rv16_lw           = opcode_1_0_00 & rv16_func3_010;//
  wire rv16_sw           = opcode_1_0_00 & rv16_func3_110;//


  wire rv16_addi         = opcode_1_0_01 & rv16_func3_000;//
  wire rv16_jal          = opcode_1_0_01 & rv16_func3_001;//
  wire rv16_li           = opcode_1_0_01 & rv16_func3_010;//
  wire rv16_lui_addi16sp = opcode_1_0_01 & rv16_func3_011;//--
  wire rv16_miscalu      = opcode_1_0_01 & rv16_func3_100;//--
  wire rv16_j            = opcode_1_0_01 & rv16_func3_101;//
  wire rv16_beqz         = opcode_1_0_01 & rv16_func3_110;//
  wire rv16_bnez         = opcode_1_0_01 & rv16_func3_111;//


  wire rv16_slli         = opcode_1_0_10 & rv16_func3_000;//
  //根据栈顶指针加载数据，详见riscv-spec-v2.2.pdf P71
  wire rv16_lwsp         = opcode_1_0_10 & rv16_func3_010;//
  //解析
  wire rv16_jalr_mv_add  = opcode_1_0_10 & rv16_func3_100;//--
  //根据栈顶指针存储数据，详见riscv-spec-v2.2.pdf P71
  wire rv16_swsp         = opcode_1_0_10 & rv16_func3_110;//

  `ifndef E203_HAS_FPU//{
  wire rv16_flw          = 1'b0;
  wire rv16_fld          = 1'b0;
  wire rv16_fsw          = 1'b0;
  wire rv16_fsd          = 1'b0;
  wire rv16_fldsp        = 1'b0;
  wire rv16_flwsp        = 1'b0;
  wire rv16_fsdsp        = 1'b0;
  wire rv16_fswsp        = 1'b0;
  `endif//}

  //不能向x0写入数据
  wire rv16_lwsp_ilgl    = rv16_lwsp & rv16_rd_x0;//(RES, rd=0)

  //判断是不是NOP指令
  wire rv16_nop          = rv16_addi
                         & (~rv16_instr[12]) & (rv16_rd_x0) & (rv16_rs2_x0);

  //16位带立即数的逻辑右移
  wire rv16_srli         = rv16_miscalu  & (rv16_instr[11:10] == 2'b00);
  //16位带立即数的算数右移
  wire rv16_srai         = rv16_miscalu  & (rv16_instr[11:10] == 2'b01);
  wire rv16_andi         = rv16_miscalu  & (rv16_instr[11:10] == 2'b10);

  wire rv16_instr_12_is0   = (rv16_instr[12] == 1'b0);
  wire rv16_instr_6_2_is0s = (rv16_instr[6:2] == 5'b0);

  wire rv16_sxxi_shamt_legl =
                 rv16_instr_12_is0 //shamt[5] must be zero for RV32C
               & (~(rv16_instr_6_2_is0s)) //shamt[4:0] must be non-zero for RV32C
                 ;
  wire rv16_sxxi_shamt_ilgl =  (rv16_slli | rv16_srli | rv16_srai) & (~rv16_sxxi_shamt_legl);

  //16位立即数和栈顶指针相加
  wire rv16_addi16sp     = rv16_lui_addi16sp & rv32_rd_x2;//
  //load upper immediate, 把rd的高20位设置为立即数，低12位设置为0
  wire rv16_lui          = rv16_lui_addi16sp & (~rv32_rd_x0) & (~rv32_rd_x2);//

  //C.LI is only valid when rd!=x0.
  wire rv16_li_ilgl = rv16_li & (rv16_rd_x0);
  //C.LUI is only valid when rd!=x0 or x2, and when the immediate is not equal to zero.
  wire rv16_lui_ilgl = rv16_lui & (rv16_rd_x0 | rv16_rd_x2 | (rv16_instr_6_2_is0s & rv16_instr_12_is0));

  wire rv16_li_lui_ilgl = rv16_li_ilgl | rv16_lui_ilgl;

  //详见riscv-spec-v2.2.pdf P77,
  //C.ADDI4SPN is a CIW-format RV32C/RV64C-only instruction that adds a zero-extended non-zero
  // immediate, scaled by 4, to the stack pointer, x2, and writes the result to rd0. This instruction is used
  // to generate pointers to stack-allocated variables, and expands to addi rd0, x2, nzuimm[9:2].
  wire rv16_addi4spn_ilgl = rv16_addi4spn & (rv16_instr_12_is0 & rv16_rd_x0 & opcode_6_5_00);//(RES, nzimm=0, bits[12:5])
  wire rv16_addi16sp_ilgl = rv16_addi16sp & rv16_instr_12_is0 & rv16_instr_6_2_is0s; //(RES, nzimm=0, bits 12,6:2)

  wire rv16_subxororand  = rv16_miscalu  & (rv16_instr[12:10] == 3'b011);//
  wire rv16_sub          = rv16_subxororand & (rv16_instr[6:5] == 2'b00);//
  wire rv16_xor          = rv16_subxororand & (rv16_instr[6:5] == 2'b01);//
  wire rv16_or           = rv16_subxororand & (rv16_instr[6:5] == 2'b10);//
  wire rv16_and          = rv16_subxororand & (rv16_instr[6:5] == 2'b11);//

  wire rv16_jr           = rv16_jalr_mv_add //
                         & (~rv16_instr[12]) & (~rv16_rs1_x0) & (rv16_rs2_x0);// The RES rs1=0 illegal is already covered here

  //C.MV copies the value in register rs2 into register rd. C.MV expands into add rd, x0, rs2.
  wire rv16_mv           = rv16_jalr_mv_add //
                         & (~rv16_instr[12]) & (~rv16_rd_x0) & (~rv16_rs2_x0);
  //Debuggers can use the C.EBREAK instruction, which expands to ebreak, to cause control to be transferred back to the debugging environment.
  wire rv16_ebreak       = rv16_jalr_mv_add //
                         & (rv16_instr[12]) & (rv16_rd_x0) & (rv16_rs2_x0);
  wire rv16_jalr         = rv16_jalr_mv_add //
                         & (rv16_instr[12]) & (~rv16_rs1_x0) & (rv16_rs2_x0);
  wire rv16_add          = rv16_jalr_mv_add //
                         & (rv16_instr[12]) & (~rv16_rd_x0) & (~rv16_rs2_x0);





  // ===========================================================================
  // Branch Instructions，判断条件跳转指令的类型
  wire rv32_beq      = rv32_branch & rv32_func3_000;
  wire rv32_bne      = rv32_branch & rv32_func3_001;
  wire rv32_blt      = rv32_branch & rv32_func3_100;
  wire rv32_bgt      = rv32_branch & rv32_func3_101;
  wire rv32_bltu     = rv32_branch & rv32_func3_110;
  wire rv32_bgtu     = rv32_branch & rv32_func3_111;

  // ===========================================================================
  // System Instructions
  wire rv32_ecall    = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0000_0000_0000);
  wire rv32_ebreak   = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0000_0000_0001);
  //以mret方式退出异常处理程序
  wire rv32_mret     = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0011_0000_0010);
  //以dret方式退出异常处理程序，从debug模式中退出
  wire rv32_dret     = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0111_1011_0010);
  //WFI: Wait For Interrupt， 中断等待指令
  wire rv32_wfi      = rv32_system & rv32_func3_000 & (rv32_instr[31:20] == 12'b0001_0000_0101);
  // We dont implement the WFI and MRET illegal exception when the rs and rd is not zeros

  //读写CSR寄存器的操作
  wire rv32_csrrw    = rv32_system & rv32_func3_001;
  wire rv32_csrrs    = rv32_system & rv32_func3_010;
  wire rv32_csrrc    = rv32_system & rv32_func3_011;
  wire rv32_csrrwi   = rv32_system & rv32_func3_101;
  wire rv32_csrrsi   = rv32_system & rv32_func3_110;
  wire rv32_csrrci   = rv32_system & rv32_func3_111;

  //非法的dret指令，不是debug模式
  wire rv32_dret_ilgl = rv32_dret & (~dbg_mode);

  //是否为除了CSR寄存器操作之外的系统调用
  wire rv32_ecall_ebreak_ret_wfi = rv32_system & rv32_func3_000;
  //是否为读写CSR寄存器的操作
  wire rv32_csr          = rv32_system & (~rv32_func3_000);


  // ===========================================================================
    // The Branch and system group of instructions will be handled by BJP

  //是不是立即数跳转指令
  assign dec_jal     = rv32_jal    | rv16_jal  | rv16_j;
  //是不是寄存器跳转指令
  assign dec_jalr    = rv32_jalr   | rv16_jalr | rv16_jr;
  //是不是条件跳转指令
  assign dec_bxx     = rv32_branch | rv16_beqz | rv16_bnez;
  //是不是跳转指令
  assign dec_bjp     = dec_jal | dec_jalr | dec_bxx;


  //FENCE 指令用于屏障“数据”存储器访问的执行顺序，详见书P394
  wire rv32_fence  ;
  //立即数屏蔽指令
  wire rv32_fence_i;
  wire rv32_fence_fencei;
  //是不是跳转指令，包括条件跳转、
  wire bjp_op = dec_bjp | rv32_mret | (rv32_dret & (~rv32_dret_ilgl)) | rv32_fence_fencei;

  //设置跳转信息总线，如果是其中的某个指令则将对应的输出设置为1
  wire [`E203_DECINFO_BJP_WIDTH-1:0] bjp_info_bus;
  assign bjp_info_bus[`E203_DECINFO_GRP    ]    = `E203_DECINFO_GRP_BJP;
  assign bjp_info_bus[`E203_DECINFO_RV32   ]    = rv32;
  assign bjp_info_bus[`E203_DECINFO_BJP_JUMP ]  = dec_jal | dec_jalr;
  assign bjp_info_bus[`E203_DECINFO_BJP_BPRDT]  = i_prdt_taken;
  assign bjp_info_bus[`E203_DECINFO_BJP_BEQ  ]  = rv32_beq | rv16_beqz;
  assign bjp_info_bus[`E203_DECINFO_BJP_BNE  ]  = rv32_bne | rv16_bnez;
  assign bjp_info_bus[`E203_DECINFO_BJP_BLT  ]  = rv32_blt;
  assign bjp_info_bus[`E203_DECINFO_BJP_BGT  ]  = rv32_bgt ;
  assign bjp_info_bus[`E203_DECINFO_BJP_BLTU ]  = rv32_bltu;
  assign bjp_info_bus[`E203_DECINFO_BJP_BGTU ]  = rv32_bgtu;
  assign bjp_info_bus[`E203_DECINFO_BJP_BXX  ]  = dec_bxx;
  assign bjp_info_bus[`E203_DECINFO_BJP_MRET ]  = rv32_mret;
  assign bjp_info_bus[`E203_DECINFO_BJP_DRET ]  = rv32_dret;
  assign bjp_info_bus[`E203_DECINFO_BJP_FENCE ]  = rv32_fence;
  assign bjp_info_bus[`E203_DECINFO_BJP_FENCEI]  = rv32_fence_i;


  // ===========================================================================
  // ALU Instructions， 解析ALU指令
  wire rv32_addi     = rv32_op_imm & rv32_func3_000;
  wire rv32_slti     = rv32_op_imm & rv32_func3_010;
  wire rv32_sltiu    = rv32_op_imm & rv32_func3_011;
  wire rv32_xori     = rv32_op_imm & rv32_func3_100;
  wire rv32_ori      = rv32_op_imm & rv32_func3_110;
  wire rv32_andi     = rv32_op_imm & rv32_func3_111;

  wire rv32_slli     = rv32_op_imm & rv32_func3_001 & (rv32_instr[31:26] == 6'b000000);
  wire rv32_srli     = rv32_op_imm & rv32_func3_101 & (rv32_instr[31:26] == 6'b000000);
  wire rv32_srai     = rv32_op_imm & rv32_func3_101 & (rv32_instr[31:26] == 6'b010000);

  //shamt: shift amount, shamt[5]必须为0，详见riscv-spec-v2.2.pdf P14
  wire rv32_sxxi_shamt_legl = (rv32_instr[25] == 1'b0); //shamt[5] must be zero for RV32I
  //非法的移位指令
  wire rv32_sxxi_shamt_ilgl =  (rv32_slli | rv32_srli | rv32_srai) & (~rv32_sxxi_shamt_legl);

  wire rv32_add      = rv32_op     & rv32_func3_000 & rv32_func7_0000000;
  wire rv32_sub      = rv32_op     & rv32_func3_000 & rv32_func7_0100000;
  wire rv32_sll      = rv32_op     & rv32_func3_001 & rv32_func7_0000000;
  wire rv32_slt      = rv32_op     & rv32_func3_010 & rv32_func7_0000000;
  wire rv32_sltu     = rv32_op     & rv32_func3_011 & rv32_func7_0000000;
  wire rv32_xor      = rv32_op     & rv32_func3_100 & rv32_func7_0000000;
  wire rv32_srl      = rv32_op     & rv32_func3_101 & rv32_func7_0000000;
  wire rv32_sra      = rv32_op     & rv32_func3_101 & rv32_func7_0100000;
  wire rv32_or       = rv32_op     & rv32_func3_110 & rv32_func7_0000000;
  wire rv32_and      = rv32_op     & rv32_func3_111 & rv32_func7_0000000;

  wire rv32_nop      = rv32_addi & rv32_rs1_x0 & rv32_rd_x0 & (~(|rv32_instr[31:20]));
  // The ALU group of instructions will be handled by 1cycle ALU-datapath
  //ecall和ebreak都是特权指令，详见riscv-spec-v2.2.pdf P24
  wire ecall_ebreak = rv32_ecall | rv32_ebreak | rv16_ebreak;

  //如果是ALU指令则为1
  wire alu_op = (~rv32_sxxi_shamt_ilgl) & (~rv16_sxxi_shamt_ilgl)
              & (~rv16_li_lui_ilgl) & (~rv16_addi4spn_ilgl) & (~rv16_addi16sp_ilgl) &
              ( rv32_op_imm
              | rv32_op & (~rv32_func7_0000001) // Exclude the MULDIV
              | rv32_auipc
              | rv32_lui
              | rv16_addi4spn
              | rv16_addi
              | rv16_lui_addi16sp
              | rv16_li | rv16_mv
              | rv16_slli
              | rv16_miscalu
              | rv16_add
              | rv16_nop | rv32_nop
              | rv32_wfi // We just put WFI into ALU and do nothing in ALU
              | ecall_ebreak)
              ;
  //用于指示是否需要立即数
  wire need_imm;
  //设置ALU信息总线，如果是其中的某个指令则将对应的输出设置为1
  wire [`E203_DECINFO_ALU_WIDTH-1:0] alu_info_bus;
  assign alu_info_bus[`E203_DECINFO_GRP    ]    = `E203_DECINFO_GRP_ALU;
  //是否为32位指令
  assign alu_info_bus[`E203_DECINFO_RV32   ]    = rv32;
  //是否为加法指令
  assign alu_info_bus[`E203_DECINFO_ALU_ADD]    = rv32_add  | rv32_addi | rv32_auipc |
                                                  rv16_addi4spn | rv16_addi | rv16_addi16sp | rv16_add |
                            // We also decode LI and MV as the add instruction, becuase
                            //   they all add x0 with a RS2 or Immeidate, and then write into RD
                                                  rv16_li | rv16_mv;
  //是否为减法指令
  assign alu_info_bus[`E203_DECINFO_ALU_SUB]    = rv32_sub  | rv16_sub;
  assign alu_info_bus[`E203_DECINFO_ALU_SLT]    = rv32_slt  | rv32_slti;
  assign alu_info_bus[`E203_DECINFO_ALU_SLTU]   = rv32_sltu | rv32_sltiu;
  assign alu_info_bus[`E203_DECINFO_ALU_XOR]    = rv32_xor  | rv32_xori | rv16_xor;
  assign alu_info_bus[`E203_DECINFO_ALU_SLL]    = rv32_sll  | rv32_slli | rv16_slli;
  assign alu_info_bus[`E203_DECINFO_ALU_SRL]    = rv32_srl  | rv32_srli | rv16_srli;
  assign alu_info_bus[`E203_DECINFO_ALU_SRA]    = rv32_sra  | rv32_srai | rv16_srai;
  assign alu_info_bus[`E203_DECINFO_ALU_OR ]    = rv32_or   | rv32_ori  | rv16_or;
  assign alu_info_bus[`E203_DECINFO_ALU_AND]    = rv32_and  | rv32_andi | rv16_andi | rv16_and;
  assign alu_info_bus[`E203_DECINFO_ALU_LUI]    = rv32_lui  | rv16_lui;
  //第二个操作数是不是立即数
  assign alu_info_bus[`E203_DECINFO_ALU_OP2IMM] = need_imm;
  assign alu_info_bus[`E203_DECINFO_ALU_OP1PC ] = rv32_auipc;
  assign alu_info_bus[`E203_DECINFO_ALU_NOP ]   = rv16_nop | rv32_nop;
  assign alu_info_bus[`E203_DECINFO_ALU_ECAL ]  = rv32_ecall;
  assign alu_info_bus[`E203_DECINFO_ALU_EBRK ]  = rv32_ebreak | rv16_ebreak;
  assign alu_info_bus[`E203_DECINFO_ALU_WFI  ]  = rv32_wfi;



  wire csr_op = rv32_csr;
  wire [`E203_DECINFO_CSR_WIDTH-1:0] csr_info_bus;
  //设置CSR操作信息总线，如果是其中的某个指令则将对应的输出设置为1
  assign csr_info_bus[`E203_DECINFO_GRP    ]    = `E203_DECINFO_GRP_CSR;
  assign csr_info_bus[`E203_DECINFO_RV32   ]    = rv32;
  assign csr_info_bus[`E203_DECINFO_CSR_CSRRW ] = rv32_csrrw | rv32_csrrwi;
  assign csr_info_bus[`E203_DECINFO_CSR_CSRRS ] = rv32_csrrs | rv32_csrrsi;
  assign csr_info_bus[`E203_DECINFO_CSR_CSRRC ] = rv32_csrrc | rv32_csrrci;
  assign csr_info_bus[`E203_DECINFO_CSR_RS1IMM] = rv32_csrrwi | rv32_csrrsi | rv32_csrrci;
  assign csr_info_bus[`E203_DECINFO_CSR_ZIMMM ] = rv32_rs1;
  assign csr_info_bus[`E203_DECINFO_CSR_RS1IS0] = rv32_rs1_x0;
  assign csr_info_bus[`E203_DECINFO_CSR_CSRIDX] = rv32_instr[31:20];


  // ===========================================================================
  // Memory Order Instructions
  //是否为用于设置内存读写顺序的指令
  assign rv32_fence    = rv32_miscmem & rv32_func3_000;
  assign rv32_fence_i  = rv32_miscmem & rv32_func3_001;

  assign rv32_fence_fencei  = rv32_miscmem;


  // ===========================================================================
  // MUL/DIV Instructions
  //乘除法指令
  wire rv32_mul      = rv32_op     & rv32_func3_000 & rv32_func7_0000001;
  wire rv32_mulh     = rv32_op     & rv32_func3_001 & rv32_func7_0000001;
  wire rv32_mulhsu   = rv32_op     & rv32_func3_010 & rv32_func7_0000001;
  wire rv32_mulhu    = rv32_op     & rv32_func3_011 & rv32_func7_0000001;
  wire rv32_div      = rv32_op     & rv32_func3_100 & rv32_func7_0000001;
  wire rv32_divu     = rv32_op     & rv32_func3_101 & rv32_func7_0000001;
  wire rv32_rem      = rv32_op     & rv32_func3_110 & rv32_func7_0000001;
  wire rv32_remu     = rv32_op     & rv32_func3_111 & rv32_func7_0000001;

  // The MULDIV group of instructions will be handled by MUL-DIV-datapath
  `ifdef E203_SUPPORT_MULDIV//{
  wire muldiv_op = rv32_op & rv32_func7_0000001;
  `endif//}
  `ifndef E203_SUPPORT_MULDIV//{
  //如果不支持硬件乘除法则恒置为0
  wire muldiv_op = 1'b0;
  `endif//}

  //设置乘除法操作信息总线，如果是其中的某个指令则将对应的输出设置为1
  wire [`E203_DECINFO_MULDIV_WIDTH-1:0] muldiv_info_bus;
  assign muldiv_info_bus[`E203_DECINFO_GRP          ] = `E203_DECINFO_GRP_MULDIV;
  assign muldiv_info_bus[`E203_DECINFO_RV32         ] = rv32        ;
  assign muldiv_info_bus[`E203_DECINFO_MULDIV_MUL   ] = rv32_mul    ;
  assign muldiv_info_bus[`E203_DECINFO_MULDIV_MULH  ] = rv32_mulh   ;
  assign muldiv_info_bus[`E203_DECINFO_MULDIV_MULHSU] = rv32_mulhsu ;
  assign muldiv_info_bus[`E203_DECINFO_MULDIV_MULHU ] = rv32_mulhu  ;
  assign muldiv_info_bus[`E203_DECINFO_MULDIV_DIV   ] = rv32_div    ;
  assign muldiv_info_bus[`E203_DECINFO_MULDIV_DIVU  ] = rv32_divu   ;
  assign muldiv_info_bus[`E203_DECINFO_MULDIV_REM   ] = rv32_rem    ;
  assign muldiv_info_bus[`E203_DECINFO_MULDIV_REMU  ] = rv32_remu   ;
  assign muldiv_info_bus[`E203_DECINFO_MULDIV_B2B   ] = i_muldiv_b2b;

  //是否为某种乘除法操作
  assign dec_mulhsu = rv32_mulh | rv32_mulhsu | rv32_mulhu;
  assign dec_mul    = rv32_mul;
  assign dec_div    = rv32_div ;
  assign dec_divu   = rv32_divu;
  assign dec_rem    = rv32_rem;
  assign dec_remu   = rv32_remu;

  // ===========================================================================
  // Load/Store Instructions
  //是否为内存读取操作，b代表1byte, 8bits, h代表hex 16bits，写入寄存器高位，w代表word，32bits
  //u代表无符号
  wire rv32_lb       = rv32_load   & rv32_func3_000;
  wire rv32_lh       = rv32_load   & rv32_func3_001;
  wire rv32_lw       = rv32_load   & rv32_func3_010;
  wire rv32_lbu      = rv32_load   & rv32_func3_100;
  wire rv32_lhu      = rv32_load   & rv32_func3_101;

  //是否为内存写入操作
  wire rv32_sb       = rv32_store  & rv32_func3_000;
  wire rv32_sh       = rv32_store  & rv32_func3_001;
  wire rv32_sw       = rv32_store  & rv32_func3_010;


  // ===========================================================================
  // Atomic Instructions
  `ifdef E203_SUPPORT_AMO//{
  //支持原子内存操作, lr: load-reserved, sc: store conditional
  wire rv32_lr_w      = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00010);
  wire rv32_sc_w      = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00011);
  wire rv32_amoswap_w = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00001);
  wire rv32_amoadd_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00000);
  wire rv32_amoxor_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b00100);
  wire rv32_amoand_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b01100);
  wire rv32_amoor_w   = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b01000);
  wire rv32_amomin_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b10000);
  wire rv32_amomax_w  = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b10100);
  wire rv32_amominu_w = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b11000);
  wire rv32_amomaxu_w = rv32_amo & rv32_func3_010 & (rv32_func7[6:2] == 5'b11100);

  `endif//E203_SUPPORT_AMO}
  `ifndef E203_SUPPORT_AMO//{
    //不支持原子内存操作, 全部置为0
  wire rv32_lr_w      = 1'b0;
  wire rv32_sc_w      = 1'b0;
  wire rv32_amoswap_w = 1'b0;
  wire rv32_amoadd_w  = 1'b0;
  wire rv32_amoxor_w  = 1'b0;
  wire rv32_amoand_w  = 1'b0;
  wire rv32_amoor_w   = 1'b0;
  wire rv32_amomin_w  = 1'b0;
  wire rv32_amomax_w  = 1'b0;
  wire rv32_amominu_w = 1'b0;
  wire rv32_amomaxu_w = 1'b0;

  `endif//}

  //是否为原子load store操作
  wire   amoldst_op = rv32_amo | rv32_load | rv32_store | rv16_lw | rv16_sw | (rv16_lwsp & (~rv16_lwsp_ilgl)) | rv16_swsp;
    // The RV16 always is word
  //lsu信息总线的位宽，(lsu: load store unit)
  wire [1:0] lsu_info_size  = rv32 ? rv32_func3[1:0] : 2'b10;
    // The RV16 always is signed
  wire       lsu_info_usign = rv32? rv32_func3[2] : 1'b0;

  //设置agu信息总线，agu: address generate unit
  wire [`E203_DECINFO_AGU_WIDTH-1:0] agu_info_bus;
  assign agu_info_bus[`E203_DECINFO_GRP    ] = `E203_DECINFO_GRP_AGU;
  assign agu_info_bus[`E203_DECINFO_RV32   ] = rv32;
  assign agu_info_bus[`E203_DECINFO_AGU_LOAD   ] = rv32_load  | rv32_lr_w | rv16_lw | rv16_lwsp;
  assign agu_info_bus[`E203_DECINFO_AGU_STORE  ] = rv32_store | rv32_sc_w | rv16_sw | rv16_swsp;
  assign agu_info_bus[`E203_DECINFO_AGU_SIZE   ] = lsu_info_size;
  assign agu_info_bus[`E203_DECINFO_AGU_USIGN  ] = lsu_info_usign;
  assign agu_info_bus[`E203_DECINFO_AGU_EXCL   ] = rv32_lr_w | rv32_sc_w;
  assign agu_info_bus[`E203_DECINFO_AGU_AMO    ] = rv32_amo & (~(rv32_lr_w | rv32_sc_w));// We seperated the EXCL out of AMO in LSU handling
  assign agu_info_bus[`E203_DECINFO_AGU_AMOSWAP] = rv32_amoswap_w;
  assign agu_info_bus[`E203_DECINFO_AGU_AMOADD ] = rv32_amoadd_w ;
  assign agu_info_bus[`E203_DECINFO_AGU_AMOAND ] = rv32_amoand_w ;
  assign agu_info_bus[`E203_DECINFO_AGU_AMOOR  ] = rv32_amoor_w ;
  assign agu_info_bus[`E203_DECINFO_AGU_AMOXOR ] = rv32_amoxor_w  ;
  assign agu_info_bus[`E203_DECINFO_AGU_AMOMAX ] = rv32_amomax_w ;
  assign agu_info_bus[`E203_DECINFO_AGU_AMOMIN ] = rv32_amomin_w ;
  assign agu_info_bus[`E203_DECINFO_AGU_AMOMAXU] = rv32_amomaxu_w;
  assign agu_info_bus[`E203_DECINFO_AGU_AMOMINU] = rv32_amominu_w;
  assign agu_info_bus[`E203_DECINFO_AGU_OP2IMM ] = need_imm;




  // Reuse the common signals as much as possible to save gatecounts
  //32位指令全0，非法指令
  wire rv32_all0s_ilgl  = rv32_func7_0000000
                        & rv32_rs2_x0
                        & rv32_rs1_x0
                        & rv32_func3_000
                        & rv32_rd_x0
                        & opcode_6_5_00
                        & opcode_4_2_000
                        & (opcode[1:0] == 2'b00);

  //32位指令全1，非法指令
  wire rv32_all1s_ilgl  = rv32_func7_1111111
                        & rv32_rs2_x31
                        & rv32_rs1_x31
                        & rv32_func3_111
                        & rv32_rd_x31
                        & opcode_6_5_11
                        & opcode_4_2_111
                        & (opcode[1:0] == 2'b11);

  //16位指令全0，非法指令
  wire rv16_all0s_ilgl  = rv16_func3_000 //rv16_func3  = rv32_instr[15:13];
                        & rv32_func3_000 //rv32_func3  = rv32_instr[14:12];
                        & rv32_rd_x0     //rv32_rd     = rv32_instr[11:7];
                        & opcode_6_5_00
                        & opcode_4_2_000
                        & (opcode[1:0] == 2'b00);

  //16位指令全1，非法指令
  wire rv16_all1s_ilgl  = rv16_func3_111
                        & rv32_func3_111
                        & rv32_rd_x31
                        & opcode_6_5_11
                        & opcode_4_2_111
                        & (opcode[1:0] == 2'b11);

  //指令全0或全1，非法指令
  wire rv_all0s1s_ilgl = rv32 ?  (rv32_all0s_ilgl | rv32_all1s_ilgl)
                              :  (rv16_all0s_ilgl | rv16_all1s_ilgl);

  //
  // All the RV32IMA need RD register except the
  //   * Branch, Store,
  //   * fence, fence_i
  //   * ecall, ebreak
  //32位指令是否需要向寄存器写入数据
  wire rv32_need_rd =
                      (~rv32_rd_x0) & (
                    (
                      (~rv32_branch) & (~rv32_store)
                    & (~rv32_fence_fencei)
                    & (~rv32_ecall_ebreak_ret_wfi)
                    )
                   );

  // All the RV32IMA need RS1 register except the
  //   * lui
  //   * auipc
  //   * jal
  //   * fence, fence_i
  //   * ecall, ebreak
  //   * csrrwi
  //   * csrrsi
  //   * csrrci
  //32位指令是否需要读取rs1对应的寄存器
  wire rv32_need_rs1 =
                      (~rv32_rs1_x0) & (
                    (
                      (~rv32_lui)
                    & (~rv32_auipc)
                    & (~rv32_jal)
                    & (~rv32_fence_fencei)
                    & (~rv32_ecall_ebreak_ret_wfi)
                    & (~rv32_csrrwi)
                    & (~rv32_csrrsi)
                    & (~rv32_csrrci)
                    )
                  );

  // Following RV32IMA instructions need RS2 register
  //   * branch
  //   * store
  //   * rv32_op
  //   * rv32_amo except the rv32_lr_w
  //32位指令是否需要读取rs2对应的寄存器
  wire rv32_need_rs2 = (~rv32_rs2_x0) & (
                (
                 (rv32_branch)
               | (rv32_store)
               | (rv32_op)
               | (rv32_amo & (~rv32_lr_w))
                 )
                 );

  //32位I-type指令的立即数
  wire [31:0]  rv32_i_imm = {
                               {20{rv32_instr[31]}} //符号扩展
                              , rv32_instr[31:20]
                             };

  //32位S-type指令的立即数
  wire [31:0]  rv32_s_imm = {
                               {20{rv32_instr[31]}} //符号扩展
                              , rv32_instr[31:25]
                              , rv32_instr[11:7]
                             };

  //32位B-type指令的立即数
  wire [31:0]  rv32_b_imm = {
                               {19{rv32_instr[31]}} //符号扩展
                              , rv32_instr[31]
                              , rv32_instr[7]
                              , rv32_instr[30:25]
                              , rv32_instr[11:8]
                              , 1'b0//最后一位补0
                              };

  //32位U-type指令的立即数
  wire [31:0]  rv32_u_imm = {rv32_instr[31:12],12'b0};

  //32位J-type指令的立即数
  wire [31:0]  rv32_j_imm = {
                               {11{rv32_instr[31]}} //符号扩展
                              , rv32_instr[31]
                              , rv32_instr[19:12]
                              , rv32_instr[20]
                              , rv32_instr[30:21]
                              , 1'b0//最后一位补0
                              };

                   // It will select i-type immediate when
                   //    * rv32_op_imm
                   //    * rv32_jalr
                   //    * rv32_load
  //rv32_imm_sel_x用于选择使用哪种立即数，
  //例如(rv32_imm_sel_i&rv32_i_imm)|(rv32_imm_sel_jal&rv32_j_imm)|(rv32_imm_sel_bxx&rv32_bxx_imm)能够选择需要的立即数
  //下面都是用于处理这种逻辑的代码
  wire rv32_imm_sel_i = rv32_op_imm | rv32_jalr | rv32_load;
  wire rv32_imm_sel_jalr = rv32_jalr;
  //对应的立即数
  wire [31:0]  rv32_jalr_imm = rv32_i_imm;

                   // It will select u-type immediate when
                   //    * rv32_lui, rv32_auipc
  wire rv32_imm_sel_u = rv32_lui | rv32_auipc;

                   // It will select j-type immediate when
                   //    * rv32_jal
  wire rv32_imm_sel_j = rv32_jal;
  wire rv32_imm_sel_jal = rv32_jal;
  wire [31:0]  rv32_jal_imm = rv32_j_imm;

                   // It will select b-type immediate when
                   //    * rv32_branch
  wire rv32_imm_sel_b = rv32_branch;
  wire rv32_imm_sel_bxx = rv32_branch;
  wire [31:0]  rv32_bxx_imm = rv32_b_imm;

                   // It will select s-type immediate when
                   //    * rv32_store
  wire rv32_imm_sel_s = rv32_store;



  //   * Note: this CIS/CILI/CILUI/CI16SP-type is named by myself, because in
  //           ISA doc, the CI format for LWSP is different
  //           with other CI formats in terms of immediate

                   // It will select CIS-type immediate when
                   //    * rv16_lwsp
  //与上面类似，只不过是用来处理16位指令的立即数
  wire rv16_imm_sel_cis = rv16_lwsp;
  wire [31:0]  rv16_cis_imm ={
                          24'b0
                        , rv16_instr[3:2]
                        , rv16_instr[12]
                        , rv16_instr[6:4]
                        , 2'b0
                         };

  wire [31:0]  rv16_cis_d_imm ={
                          23'b0
                        , rv16_instr[4:2]
                        , rv16_instr[12]
                        , rv16_instr[6:5]
                        , 3'b0
                         };
                   // It will select CILI-type immediate when
                   //    * rv16_li
                   //    * rv16_addi
                   //    * rv16_slli
                   //    * rv16_srai
                   //    * rv16_srli
                   //    * rv16_andi
  wire rv16_imm_sel_cili = rv16_li | rv16_addi | rv16_slli
                   | rv16_srai | rv16_srli | rv16_andi;
  wire [31:0]  rv16_cili_imm ={
                          {26{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[6:2]
                         };

                   // It will select CILUI-type immediate when
                   //    * rv16_lui
  wire rv16_imm_sel_cilui = rv16_lui;
  wire [31:0]  rv16_cilui_imm ={
                          {14{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[6:2]
                        , 12'b0
                         };

                   // It will select CI16SP-type immediate when
                   //    * rv16_addi16sp
  wire rv16_imm_sel_ci16sp = rv16_addi16sp;
  wire [31:0]  rv16_ci16sp_imm ={
                          {22{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[4]
                        , rv16_instr[3]
                        , rv16_instr[5]
                        , rv16_instr[2]
                        , rv16_instr[6]
                        , 4'b0
                         };

                   // It will select CSS-type immediate when
                   //    * rv16_swsp
  wire rv16_imm_sel_css = rv16_swsp;
  wire [31:0]  rv16_css_imm ={
                          24'b0
                        , rv16_instr[8:7]
                        , rv16_instr[12:9]
                        , 2'b0
                         };
  wire [31:0]  rv16_css_d_imm ={
                          23'b0
                        , rv16_instr[9:7]
                        , rv16_instr[12:10]
                        , 3'b0
                         };
                   // It will select CIW-type immediate when
                   //    * rv16_addi4spn
  wire rv16_imm_sel_ciw = rv16_addi4spn;
  wire [31:0]  rv16_ciw_imm ={
                          22'b0
                        , rv16_instr[10:7]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[5]
                        , rv16_instr[6]
                        , 2'b0
                         };

                   // It will select CL-type immediate when
                   //    * rv16_lw
  wire rv16_imm_sel_cl = rv16_lw;
  wire [31:0]  rv16_cl_imm ={
                          25'b0
                        , rv16_instr[5]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[10]
                        , rv16_instr[6]
                        , 2'b0
                         };

  wire [31:0]  rv16_cl_d_imm ={
                          24'b0
                        , rv16_instr[6]
                        , rv16_instr[5]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[10]
                        , 3'b0
                         };
                   // It will select CS-type immediate when
                   //    * rv16_sw
  wire rv16_imm_sel_cs = rv16_sw;
  wire [31:0]  rv16_cs_imm ={
                          25'b0
                        , rv16_instr[5]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[10]
                        , rv16_instr[6]
                        , 2'b0
                         };
   wire [31:0]  rv16_cs_d_imm ={
                          24'b0
                        , rv16_instr[6]
                        , rv16_instr[5]
                        , rv16_instr[12]
                        , rv16_instr[11]
                        , rv16_instr[10]
                        , 3'b0
                         };

                   // It will select CB-type immediate when
                   //    * rv16_beqz
                   //    * rv16_bnez
  wire rv16_imm_sel_cb = rv16_beqz | rv16_bnez;
  wire [31:0]  rv16_cb_imm ={
                          {23{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[6:5]
                        , rv16_instr[2]
                        , rv16_instr[11:10]
                        , rv16_instr[4:3]
                        , 1'b0
                         };
  wire [31:0]  rv16_bxx_imm = rv16_cb_imm;

                   // It will select CJ-type immediate when
                   //    * rv16_j
                   //    * rv16_jal
  wire rv16_imm_sel_cj = rv16_j | rv16_jal;
  wire [31:0]  rv16_cj_imm ={
                          {20{rv16_instr[12]}}
                        , rv16_instr[12]
                        , rv16_instr[8]
                        , rv16_instr[10:9]
                        , rv16_instr[6]
                        , rv16_instr[7]
                        , rv16_instr[2]
                        , rv16_instr[11]
                        , rv16_instr[5:3]
                        , 1'b0
                         };
  wire [31:0]  rv16_jjal_imm = rv16_cj_imm;

                   // It will select CR-type register (no-imm) when
                   //    * rv16_jalr_mv_add
  wire [31:0]  rv16_jrjalr_imm = 32'b0;

                   // It will select CSR-type register (no-imm) when
                   //    * rv16_subxororand


  wire [31:0]  rv32_load_fp_imm  = rv32_i_imm;
  wire [31:0]  rv32_store_fp_imm = rv32_s_imm;
  wire [31:0]  rv32_imm =
                     ({32{rv32_imm_sel_i}} & rv32_i_imm)
                   | ({32{rv32_imm_sel_s}} & rv32_s_imm)
                   | ({32{rv32_imm_sel_b}} & rv32_b_imm)
                   | ({32{rv32_imm_sel_u}} & rv32_u_imm)
                   | ({32{rv32_imm_sel_j}} & rv32_j_imm)
                   ;

  wire  rv32_need_imm =
                     rv32_imm_sel_i
                   | rv32_imm_sel_s
                   | rv32_imm_sel_b
                   | rv32_imm_sel_u
                   | rv32_imm_sel_j
                   ;

  wire [31:0]  rv16_imm =
                     ({32{rv16_imm_sel_cis   }} & rv16_cis_imm)
                   | ({32{rv16_imm_sel_cili  }} & rv16_cili_imm)
                   | ({32{rv16_imm_sel_cilui }} & rv16_cilui_imm)
                   | ({32{rv16_imm_sel_ci16sp}} & rv16_ci16sp_imm)
                   | ({32{rv16_imm_sel_css   }} & rv16_css_imm)
                   | ({32{rv16_imm_sel_ciw   }} & rv16_ciw_imm)
                   | ({32{rv16_imm_sel_cl    }} & rv16_cl_imm)
                   | ({32{rv16_imm_sel_cs    }} & rv16_cs_imm)
                   | ({32{rv16_imm_sel_cb    }} & rv16_cb_imm)
                   | ({32{rv16_imm_sel_cj    }} & rv16_cj_imm)
                   ;

  wire rv16_need_imm =
                     rv16_imm_sel_cis
                   | rv16_imm_sel_cili
                   | rv16_imm_sel_cilui
                   | rv16_imm_sel_ci16sp
                   | rv16_imm_sel_css
                   | rv16_imm_sel_ciw
                   | rv16_imm_sel_cl
                   | rv16_imm_sel_cs
                   | rv16_imm_sel_cb
                   | rv16_imm_sel_cj
                   ;

  //是否需要立即数
  assign need_imm = rv32 ? rv32_need_imm : rv16_need_imm;

  //解码得到的立即数
  assign dec_imm = rv32 ? rv32_imm : rv16_imm;
  //解码得到的pc，和输入的pc相同
  assign dec_pc  = i_pc;


  //设置dec信息总线
  //{`E203_DECINFO_WIDTH{alu_op}}     & {{`E203_DECINFO_WIDTH-`E203_DECINFO_ALU_WIDTH{1'b0}},alu_info_bus}
  //如果是ALU操作则{`E203_DECINFO_WIDTH{alu_op}} 是一串1, 和后面的信息and后使得其他类型的总线上的信息被屏蔽
  assign dec_info =
              ({`E203_DECINFO_WIDTH{alu_op}}     & {{`E203_DECINFO_WIDTH-`E203_DECINFO_ALU_WIDTH{1'b0}},alu_info_bus})
            | ({`E203_DECINFO_WIDTH{amoldst_op}} & {{`E203_DECINFO_WIDTH-`E203_DECINFO_AGU_WIDTH{1'b0}},agu_info_bus})
            | ({`E203_DECINFO_WIDTH{bjp_op}}     & {{`E203_DECINFO_WIDTH-`E203_DECINFO_BJP_WIDTH{1'b0}},bjp_info_bus})
            | ({`E203_DECINFO_WIDTH{csr_op}}     & {{`E203_DECINFO_WIDTH-`E203_DECINFO_CSR_WIDTH{1'b0}},csr_info_bus})
            | ({`E203_DECINFO_WIDTH{muldiv_op}}  & {{`E203_DECINFO_WIDTH-`E203_DECINFO_CSR_WIDTH{1'b0}},muldiv_info_bus})
              ;

  //是否为合法的操作
  wire legl_ops =
              alu_op
            | amoldst_op
            | bjp_op
            | csr_op
            | muldiv_op
            ;

  // To decode the registers for Rv16, divided into 8 groups
  //cr: 需要读写通用寄存器的指令
  wire rv16_format_cr  = rv16_jalr_mv_add;
  //C.FLDSP is an RV32DC/RV64DC-only instruction that loads a double-precision floating-point value from memory into floating-point register rd.
  //ci: 立即数指令
  wire rv16_format_ci  = rv16_lwsp | rv16_flwsp | rv16_fldsp | rv16_li | rv16_lui_addi16sp | rv16_addi | rv16_slli;
  //C.FSDSP is an RV32DC/RV64DC-only instruction that stores a double-precision floating-point value in floating-point register rs2 to memory.
  //css: 需要stack pointer的写内存指令(stack pointer store)
  wire rv16_format_css = rv16_swsp | rv16_fswsp | rv16_fsdsp;
  wire rv16_format_ciw = rv16_addi4spn;
  //cl: 内存读取
  wire rv16_format_cl  = rv16_lw | rv16_flw | rv16_fld;
  //cl: 内存写入
  wire rv16_format_cs  = rv16_sw | rv16_fsw | rv16_fsd | rv16_subxororand;
  wire rv16_format_cb  = rv16_beqz | rv16_bnez | rv16_srli | rv16_srai | rv16_andi;
  //cj: 绝对跳转
  wire rv16_format_cj  = rv16_j | rv16_jal;


  //下面的代码用于判断16位指令是否需要读写寄存器，指令需要读写的寄存器的信息见riscv-spec-v2.2.pdf P70 Table 12.1
  // In CR Cases:
  //   * JR:     rs1= rs1(coded),     rs2= x0 (coded),   rd = x0 (implicit)
  //   * JALR:   rs1= rs1(coded),     rs2= x0 (coded),   rd = x1 (implicit)
  //   * MV:     rs1= x0 (implicit),  rs2= rs2(coded),   rd = rd (coded)
  //   * ADD:    rs1= rs1(coded),     rs2= rs2(coded),   rd = rd (coded)
  //   * eBreak: rs1= rs1(coded),     rs2= x0 (coded),   rd = x0 (coded)
  wire rv16_need_cr_rs1   = rv16_format_cr & 1'b1;
  wire rv16_need_cr_rs2   = rv16_format_cr & 1'b1;
  wire rv16_need_cr_rd    = rv16_format_cr & 1'b1;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cr_rs1 = rv16_mv ? `E203_RFIDX_WIDTH'd0 : rv16_rs1[`E203_RFIDX_WIDTH-1:0];
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cr_rs2 = rv16_rs2[`E203_RFIDX_WIDTH-1:0];
     // The JALR and JR difference in encoding is just the rv16_instr[12]
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cr_rd  = (rv16_jalr | rv16_jr)?
                 {{`E203_RFIDX_WIDTH-1{1'b0}},rv16_instr[12]} : rv16_rd[`E203_RFIDX_WIDTH-1:0];

  // In CI Cases:
  //   * LWSP:     rs1= x2 (implicit),  rd = rd
  //   * LI/LUI:   rs1= x0 (implicit),  rd = rd
  //   * ADDI:     rs1= rs1(implicit),  rd = rd
  //   * ADDI16SP: rs1= rs1(implicit),  rd = rd
  //   * SLLI:     rs1= rs1(implicit),  rd = rd
  wire rv16_need_ci_rs1   = rv16_format_ci & 1'b1;
  wire rv16_need_ci_rs2   = rv16_format_ci & 1'b0;
  wire rv16_need_ci_rd    = rv16_format_ci & 1'b1;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_ci_rs1 = (rv16_lwsp | rv16_flwsp | rv16_fldsp) ? `E203_RFIDX_WIDTH'd2 :
                                  (rv16_li | rv16_lui) ? `E203_RFIDX_WIDTH'd0 : rv16_rs1[`E203_RFIDX_WIDTH-1:0];
  wire [`E203_RFIDX_WIDTH-1:0] rv16_ci_rs2 = `E203_RFIDX_WIDTH'd0;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_ci_rd  = rv16_rd[`E203_RFIDX_WIDTH-1:0];

  // In CSS Cases:
  //   * SWSP:     rs1 = x2 (implicit), rs2= rs2
  wire rv16_need_css_rs1  = rv16_format_css & 1'b1;
  wire rv16_need_css_rs2  = rv16_format_css & 1'b1;
  wire rv16_need_css_rd   = rv16_format_css & 1'b0;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_css_rs1 = `E203_RFIDX_WIDTH'd2;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_css_rs2 = rv16_rs2[`E203_RFIDX_WIDTH-1:0];
  wire [`E203_RFIDX_WIDTH-1:0] rv16_css_rd  = `E203_RFIDX_WIDTH'd0;

  // In CIW cases:
  //   * ADDI4SPN:   rdd = rdd, rss1= x2 (implicit)
  wire rv16_need_ciw_rss1 = rv16_format_ciw & 1'b1;
  wire rv16_need_ciw_rss2 = rv16_format_ciw & 1'b0;
  wire rv16_need_ciw_rdd  = rv16_format_ciw & 1'b1;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_ciw_rss1  = `E203_RFIDX_WIDTH'd2;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_ciw_rss2  = `E203_RFIDX_WIDTH'd0;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_ciw_rdd  = rv16_rdd[`E203_RFIDX_WIDTH-1:0];

  // In CL cases:
  //   * LW:   rss1 = rss1, rdd= rdd
  wire rv16_need_cl_rss1  = rv16_format_cl & 1'b1;
  wire rv16_need_cl_rss2  = rv16_format_cl & 1'b0;
  wire rv16_need_cl_rdd   = rv16_format_cl & 1'b1;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cl_rss1 = rv16_rss1[`E203_RFIDX_WIDTH-1:0];
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cl_rss2 = `E203_RFIDX_WIDTH'd0;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cl_rdd  = rv16_rdd[`E203_RFIDX_WIDTH-1:0];

  // In CS cases:
  //   * SW:            rdd = none(implicit), rss1= rss1       , rss2=rss2
  //   * SUBXORORAND:   rdd = rss1,           rss1= rss1(coded), rss2=rss2
  wire rv16_need_cs_rss1  = rv16_format_cs & 1'b1;
  wire rv16_need_cs_rss2  = rv16_format_cs & 1'b1;
  wire rv16_need_cs_rdd   = rv16_format_cs & rv16_subxororand;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cs_rss1 = rv16_rss1[`E203_RFIDX_WIDTH-1:0];
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cs_rss2 = rv16_rss2[`E203_RFIDX_WIDTH-1:0];
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cs_rdd  = rv16_rss1[`E203_RFIDX_WIDTH-1:0];

  // In CB cases:
  //   * BEQ/BNE:            rdd = none(implicit), rss1= rss1, rss2=x0(implicit)
  //   * SRLI/SRAI/ANDI:     rdd = rss1          , rss1= rss1, rss2=none(implicit)
  wire rv16_need_cb_rss1  = rv16_format_cb & 1'b1;
  wire rv16_need_cb_rss2  = rv16_format_cb & (rv16_beqz | rv16_bnez);
  wire rv16_need_cb_rdd   = rv16_format_cb & (~(rv16_beqz | rv16_bnez));
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cb_rss1 = rv16_rss1[`E203_RFIDX_WIDTH-1:0];
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cb_rss2 = `E203_RFIDX_WIDTH'd0;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cb_rdd  = rv16_rss1[`E203_RFIDX_WIDTH-1:0];

  // In CJ cases:
  //   * J:            rdd = x0(implicit)
  //   * JAL:          rdd = x1(implicit)
  wire rv16_need_cj_rss1  = rv16_format_cj & 1'b0;
  wire rv16_need_cj_rss2  = rv16_format_cj & 1'b0;
  wire rv16_need_cj_rdd   = rv16_format_cj & 1'b1;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cj_rss1 = `E203_RFIDX_WIDTH'd0;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cj_rss2 = `E203_RFIDX_WIDTH'd0;
  wire [`E203_RFIDX_WIDTH-1:0] rv16_cj_rdd  = rv16_j ? `E203_RFIDX_WIDTH'd0 : `E203_RFIDX_WIDTH'd1;

  // rv16_format_cr
  // rv16_format_ci
  // rv16_format_css
  // rv16_format_ciw
  // rv16_format_cl
  // rv16_format_cs
  // rv16_format_cb
  // rv16_format_cj
  //是否需要rs1
  wire rv16_need_rs1 = rv16_need_cr_rs1 | rv16_need_ci_rs1 | rv16_need_css_rs1;
  //是否需要rs2
  wire rv16_need_rs2 = rv16_need_cr_rs2 | rv16_need_ci_rs2 | rv16_need_css_rs2;
  //是否需要rd
  wire rv16_need_rd  = rv16_need_cr_rd  | rv16_need_ci_rd  | rv16_need_css_rd;

  //是否需要rs'1
  wire rv16_need_rss1 = rv16_need_ciw_rss1|rv16_need_cl_rss1|rv16_need_cs_rss1|rv16_need_cb_rss1|rv16_need_cj_rss1;
  //是否需要rs'2
  wire rv16_need_rss2 = rv16_need_ciw_rss2|rv16_need_cl_rss2|rv16_need_cs_rss2|rv16_need_cb_rss2|rv16_need_cj_rss2;
  //是否需要rd'
  wire rv16_need_rdd  = rv16_need_ciw_rdd |rv16_need_cl_rdd |rv16_need_cs_rdd |rv16_need_cb_rdd |rv16_need_cj_rdd ;

  //16位指令的rs1使能信号
  wire rv16_rs1en = (rv16_need_rs1 | rv16_need_rss1);
  //16位指令的rs2使能信号
  wire rv16_rs2en = (rv16_need_rs2 | rv16_need_rss2);
  //16位指令的rd使能信号
  wire rv16_rden  = (rv16_need_rd  | rv16_need_rdd );

  //16位指令的rs1序号
  wire [`E203_RFIDX_WIDTH-1:0] rv16_rs1idx;
  //16位指令的rs2序号
  wire [`E203_RFIDX_WIDTH-1:0] rv16_rs2idx;
  //16位指令的rd序号
  wire [`E203_RFIDX_WIDTH-1:0] rv16_rdidx ;

  //使用并行多路选择器选择对应的16位指令的rs1序号
  assign rv16_rs1idx =
         ({`E203_RFIDX_WIDTH{rv16_need_cr_rs1 }} & rv16_cr_rs1)
       | ({`E203_RFIDX_WIDTH{rv16_need_ci_rs1 }} & rv16_ci_rs1)
       | ({`E203_RFIDX_WIDTH{rv16_need_css_rs1}} & rv16_css_rs1)
       | ({`E203_RFIDX_WIDTH{rv16_need_ciw_rss1}} & rv16_ciw_rss1)
       | ({`E203_RFIDX_WIDTH{rv16_need_cl_rss1}}  & rv16_cl_rss1)
       | ({`E203_RFIDX_WIDTH{rv16_need_cs_rss1}}  & rv16_cs_rss1)
       | ({`E203_RFIDX_WIDTH{rv16_need_cb_rss1}}  & rv16_cb_rss1)
       | ({`E203_RFIDX_WIDTH{rv16_need_cj_rss1}}  & rv16_cj_rss1)
       ;

  //使用并行多路选择器选择对应的16位指令的rs2序号
  assign rv16_rs2idx =
         ({`E203_RFIDX_WIDTH{rv16_need_cr_rs2 }} & rv16_cr_rs2)
       | ({`E203_RFIDX_WIDTH{rv16_need_ci_rs2 }} & rv16_ci_rs2)
       | ({`E203_RFIDX_WIDTH{rv16_need_css_rs2}} & rv16_css_rs2)
       | ({`E203_RFIDX_WIDTH{rv16_need_ciw_rss2}} & rv16_ciw_rss2)
       | ({`E203_RFIDX_WIDTH{rv16_need_cl_rss2}}  & rv16_cl_rss2)
       | ({`E203_RFIDX_WIDTH{rv16_need_cs_rss2}}  & rv16_cs_rss2)
       | ({`E203_RFIDX_WIDTH{rv16_need_cb_rss2}}  & rv16_cb_rss2)
       | ({`E203_RFIDX_WIDTH{rv16_need_cj_rss2}}  & rv16_cj_rss2)
       ;
  //使用并行多路选择器选择对应的16位指令的rd序号
  assign rv16_rdidx =
         ({`E203_RFIDX_WIDTH{rv16_need_cr_rd }} & rv16_cr_rd)
       | ({`E203_RFIDX_WIDTH{rv16_need_ci_rd }} & rv16_ci_rd)
       | ({`E203_RFIDX_WIDTH{rv16_need_css_rd}} & rv16_css_rd)
       | ({`E203_RFIDX_WIDTH{rv16_need_ciw_rdd}} & rv16_ciw_rdd)
       | ({`E203_RFIDX_WIDTH{rv16_need_cl_rdd}}  & rv16_cl_rdd)
       | ({`E203_RFIDX_WIDTH{rv16_need_cs_rdd}}  & rv16_cs_rdd)
       | ({`E203_RFIDX_WIDTH{rv16_need_cb_rdd}}  & rv16_cb_rdd)
       | ({`E203_RFIDX_WIDTH{rv16_need_cj_rdd}}  & rv16_cj_rdd)
       ;

  //指令的rs1序号
  assign dec_rs1idx = rv32 ? rv32_rs1[`E203_RFIDX_WIDTH-1:0] : rv16_rs1idx;
  //指令的rs2序号
  assign dec_rs2idx = rv32 ? rv32_rs2[`E203_RFIDX_WIDTH-1:0] : rv16_rs2idx;
  //指令的rd序号
  assign dec_rdidx  = rv32 ? rv32_rd [`E203_RFIDX_WIDTH-1:0] : rv16_rdidx ;

  //指令的rs1使能信号
  assign dec_rs1en = rv32 ? rv32_need_rs1 : (rv16_rs1en & (~(rv16_rs1idx == `E203_RFIDX_WIDTH'b0)));
  //指令的rs2使能信号
  assign dec_rs2en = rv32 ? rv32_need_rs2 : (rv16_rs2en & (~(rv16_rs2idx == `E203_RFIDX_WIDTH'b0)));
  //指令的rd使能信号
  assign dec_rdwen = rv32 ? rv32_need_rd  : (rv16_rden  & (~(rv16_rdidx  == `E203_RFIDX_WIDTH'b0)));

  //rs1是否为x0
  assign dec_rs1x0 = (dec_rs1idx == `E203_RFIDX_WIDTH'b0);
  //rs2是否为x0
  assign dec_rs2x0 = (dec_rs2idx == `E203_RFIDX_WIDTH'b0);

  //通用寄存器序号是否合法
  wire rv_index_ilgl;
  `ifdef E203_RFREG_NUM_IS_4 //{
    //4个通用寄存器，只能使用低两位，其他位必须为0(全部and起来之后是0)
  assign rv_index_ilgl =
                 (| dec_rs1idx[`E203_RFIDX_WIDTH-1:2])
                |(| dec_rs2idx[`E203_RFIDX_WIDTH-1:2])
                |(| dec_rdidx [`E203_RFIDX_WIDTH-1:2])
                ;
  `endif//}
  `ifdef E203_RFREG_NUM_IS_8 //{
    //8个通用寄存器，只能使用低三位，其他位必须为0(全部and起来之后是0)
  assign rv_index_ilgl =
                 (| dec_rs1idx[`E203_RFIDX_WIDTH-1:3])
                |(| dec_rs2idx[`E203_RFIDX_WIDTH-1:3])
                |(| dec_rdidx [`E203_RFIDX_WIDTH-1:3])
                ;
  `endif//}
  `ifdef E203_RFREG_NUM_IS_16 //{
    //16个通用寄存器，只能使用低四位，其他位必须为0(全部and起来之后是0)
  assign rv_index_ilgl =
                 (| dec_rs1idx[`E203_RFIDX_WIDTH-1:4])
                |(| dec_rs2idx[`E203_RFIDX_WIDTH-1:4])
                |(| dec_rdidx [`E203_RFIDX_WIDTH-1:4])
                ;
  `endif//}
  `ifdef E203_RFREG_NUM_IS_32 //{
    //32个通用寄存器，不会出现错误
      //Never happen this illegal exception
  assign rv_index_ilgl = 1'b0;
  `endif//}

  //是否为32位指令
  assign dec_rv32 = rv32;

  //跳转指令(条件跳转、无条件跳转)的立即数
  assign dec_bjp_imm =
                     ({32{rv16_jal | rv16_j     }} & rv16_jjal_imm)
                   | ({32{rv16_jalr_mv_add      }} & rv16_jrjalr_imm)
                   | ({32{rv16_beqz | rv16_bnez }} & rv16_bxx_imm)
                   | ({32{rv32_jal              }} & rv32_jal_imm)
                   | ({32{rv32_jalr             }} & rv32_jalr_imm)
                   | ({32{rv32_branch           }} & rv32_bxx_imm)
                   ;
  //保存jalr跳转的地址的寄存器
  assign dec_jalr_rs1idx = rv32 ? rv32_rs1[`E203_RFIDX_WIDTH-1:0] : rv16_rs1[`E203_RFIDX_WIDTH-1:0];
  //对齐错误
  assign dec_misalgn = i_misalgn;
  //总线错误
  assign dec_buserr  = i_buserr ;


  //解码的指令非法
  assign dec_ilegl =
            (rv_all0s1s_ilgl)
          | (rv_index_ilgl)
          | (rv16_addi16sp_ilgl)
          | (rv16_addi4spn_ilgl)
          | (rv16_li_lui_ilgl)
          | (rv16_sxxi_shamt_ilgl)
          | (rv32_sxxi_shamt_ilgl)
          | (rv32_dret_ilgl)
          | (rv16_lwsp_ilgl)
          | (~legl_ops);


endmodule



