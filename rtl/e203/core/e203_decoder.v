// --------- add/modify/delete code ---------
module e203_decoder(
  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The IFU IR stage to decoder interface
  input  [`E203_INSTR_SIZE-1:0] i_ir,// The instruction register
  input  [`E203_PC_SIZE-1:0] i_pc,   // The PC register along with
  input  i_misalgn,              // The fetch misalign
  input  i_buserr,               // The fetch bus error
  input  i_prdt_taken,
  input  i_muldiv_b2b,
  input  [`E203_RFIDX_WIDTH-1:0] i_rs1idx,   // The RS1 index
  input  [`E203_RFIDX_WIDTH-1:0] i_rs2idx,   // The RS2 index


  input  dbg_mode,


  output dec2ifu_mulhsu,
  output dec2ifu_div   ,
  output dec2ifu_rem   ,
  output dec2ifu_divu  ,
  output dec2ifu_remu  ,


  //////////////////////////////////////////////////////////////
  // The Decoded Info-Bus
  //rd序号
  output [`E203_RFIDX_WIDTH-1:0] dec_rdidx,


  //////////////////////////////////////////////////////////////
  //dispatch interface to exu
  input  wfi_halt_exu_req,
  output wfi_halt_exu_ack,
  
  input  oitf_empty,
  input  amo_wait,
  //////////////////////////////////////////////////////////////
  // The operands and decode info from dispatch
  input  disp_i_valid, // Handshake valid
  output disp_i_ready, // Handshake ready 



  // The operand 1/2 data
  input  [`E203_XLEN-1:0] disp_i_rs1,
  input  [`E203_XLEN-1:0] disp_i_rs2,


  //////////////////////////////////////////////////////////////
  // Dispatch to ALU
  output disp_o_alu_valid, 
  input  disp_o_alu_ready,

  // alu 计算完是否是longpipe，具体计算过程在i_longpipe这个值的alu里面的赋值的地方
  input  disp_o_alu_longpipe,

  output [`E203_XLEN-1:0] disp_o_alu_rs1,
  output [`E203_XLEN-1:0] disp_o_alu_rs2,
  output disp_o_alu_rdwen,
  output [`E203_RFIDX_WIDTH-1:0] disp_o_alu_rdidx,
  output [`E203_DECINFO_WIDTH-1:0]  disp_o_alu_info,  
  output [`E203_XLEN-1:0] disp_o_alu_imm,
  output [`E203_PC_SIZE-1:0] disp_o_alu_pc,
  // 直接将由OITF传递过来的队列尾部ITAG传递出去
  output [`E203_ITAG_WIDTH-1:0] disp_o_alu_itag,
  output disp_o_alu_misalgn,
  output disp_o_alu_buserr ,
  output disp_o_alu_ilegl  ,

  //////////////////////////////////////////////////////////////
  // Dispatch to OITF
  //oitf中的某条指令和源操作数match，说明有RAW依赖
  input  oitfrd_match_disprs1,
  input  oitfrd_match_disprs2,
  input  oitfrd_match_disprs3,
  //oitf中的某条指令和目标操作数match，说明有WAW依赖
  input  oitfrd_match_disprd,
  // 由OITF传递过来的队列尾部ITAG
  input  [`E203_ITAG_WIDTH-1:0] disp_oitf_ptr ,

  // 也就是和alu握手完成并且通过alu计算确定是长指令了（现在只有乘除法和LS操作），才会ena
  output disp_oitf_ena,
  //oitf是否ready，也就是oitf是不是没有满
  input  disp_oitf_ready,

  output disp_oitf_rs1fpu,
  output disp_oitf_rs2fpu,
  output disp_oitf_rs3fpu,
  output disp_oitf_rdfpu ,

  output disp_oitf_rs1en ,
  output disp_oitf_rs2en ,
  output disp_oitf_rs3en ,
  output disp_oitf_rdwen ,

  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rs1idx,
  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rs2idx,
  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rs3idx,
  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rdidx ,

  output [`E203_PC_SIZE-1:0] disp_oitf_pc ,

  input  clk,
  input  rst_n

);

 //////////////////////////////////////////////////////////////
  // Instantiate the Decode
  //译码信息输出
  wire [`E203_DECINFO_WIDTH-1:0]  dec_info;
  
  //rs1是不是x0
  wire dec_rs1x0;
  //rs2是不是x0
  wire dec_rs2x0;
  //rs1读取使能
  wire dec_rs1en;
  //rs2读取使能
  wire dec_rs2en;
  //rd写使能
  wire dec_rdwen;
  //译码得到的立即数
  wire [`E203_XLEN-1:0] dec_imm;
  //译码后更新的PC
  wire [`E203_PC_SIZE-1:0] dec_pc;
  
  
  //译码未对齐
  wire dec_misalgn;
  //译码总线错误
  wire dec_buserr;
  //译码错误
  wire dec_ilegl;


  //////////////////////////////////////////////////////////////
  // The Decoded Info-Bus
  e203_exu_decode u_e203_exu_decode (
    .dbg_mode     (dbg_mode),

    .i_instr      (i_ir    ),
    .i_pc         (i_pc    ),
    .i_misalgn    (i_misalgn),
    .i_buserr     (i_buserr ),
    .i_prdt_taken (i_prdt_taken),
    .i_muldiv_b2b (i_muldiv_b2b),

    .dec_rv32  (),
    .dec_bjp   (),
    .dec_jal   (),
    .dec_jalr  (),
    .dec_bxx   (),
    .dec_jalr_rs1idx(),
    .dec_bjp_imm(),

    .dec_mulhsu  (dec2ifu_mulhsu),
    .dec_mul     (),
    .dec_div     (dec2ifu_div   ),
    .dec_rem     (dec2ifu_rem   ),
    .dec_divu    (dec2ifu_divu  ),
    .dec_remu    (dec2ifu_remu  ),




    .dec_info  (dec_info ),
    .dec_rs1x0 (dec_rs1x0),
    .dec_rs2x0 (dec_rs2x0),
    .dec_rs1en (dec_rs1en),
    .dec_rs2en (dec_rs2en),
    .dec_rdwen (dec_rdwen),
    .dec_rs1idx(),
    .dec_rs2idx(),
    .dec_misalgn(dec_misalgn),
    .dec_buserr (dec_buserr ),
    .dec_ilegl  (dec_ilegl),
    .dec_rdidx (dec_rdidx),
    .dec_pc    (dec_pc),
    .dec_imm   (dec_imm)
  );


  e203_exu_disp u_e203_exu_disp(
    .wfi_halt_exu_req    (wfi_halt_exu_req),
    .wfi_halt_exu_ack    (wfi_halt_exu_ack),
    .oitf_empty          (oitf_empty),

    .amo_wait            (amo_wait),

    .disp_i_valid        (disp_i_valid         ),
    .disp_i_ready        (disp_i_ready         ),

    .disp_i_rs1x0        (dec_rs1x0       ),
    .disp_i_rs2x0        (dec_rs2x0       ),
    .disp_i_rs1en        (dec_rs1en       ),
    .disp_i_rs2en        (dec_rs2en       ),
    .disp_i_rs1idx       (i_rs1idx      ),
    .disp_i_rs2idx       (i_rs2idx      ),
    // input
    .disp_i_rdwen        (dec_rdwen       ),
    .disp_i_rdidx        (dec_rdidx       ),
    .disp_i_info         (dec_info        ),
    .disp_i_rs1          (disp_i_rs1          ),
    .disp_i_rs2          (disp_i_rs2          ),
    .disp_i_imm          (dec_imm        ),
    .disp_i_pc           (dec_pc         ),
    .disp_i_misalgn      (dec_misalgn    ),
    .disp_i_buserr       (dec_buserr     ),
    .disp_i_ilegl        (dec_ilegl      ),


    .disp_o_alu_valid    (disp_o_alu_valid   ),
    .disp_o_alu_ready    (disp_o_alu_ready   ),
    .disp_o_alu_longpipe (disp_o_alu_longpipe),
    // // 直接将由OITF传递过来的队列尾部ITAG传递出去
    .disp_o_alu_itag     (disp_o_alu_itag    ),
    .disp_o_alu_rs1      (disp_o_alu_rs1     ),
    .disp_o_alu_rs2      (disp_o_alu_rs2     ),
    .disp_o_alu_rdwen    (disp_o_alu_rdwen    ),
    .disp_o_alu_rdidx    (disp_o_alu_rdidx   ),
    .disp_o_alu_info     (disp_o_alu_info    ),
    .disp_o_alu_pc       (disp_o_alu_pc      ),
    .disp_o_alu_imm      (disp_o_alu_imm     ),
    .disp_o_alu_misalgn  (disp_o_alu_misalgn    ),
    .disp_o_alu_buserr   (disp_o_alu_buserr     ),
    .disp_o_alu_ilegl    (disp_o_alu_ilegl      ),

    .disp_oitf_ena       (disp_oitf_ena    ),
    .disp_oitf_ptr       (disp_oitf_ptr    ),
    .disp_oitf_ready     (disp_oitf_ready  ),

    .disp_oitf_rs1en     (disp_oitf_rs1en),
    .disp_oitf_rs2en     (disp_oitf_rs2en),
    // 永远是1位0, 但是如果用了FPU就是FPU的参数了，也就是说浮点数计算会用到三个操作数的使能控制
    .disp_oitf_rs3en     (disp_oitf_rs3en),
    .disp_oitf_rdwen     (disp_oitf_rdwen ),
    .disp_oitf_rs1idx    (disp_oitf_rs1idx),
    .disp_oitf_rs2idx    (disp_oitf_rs2idx),
    .disp_oitf_rs3idx    (disp_oitf_rs3idx),
    .disp_oitf_rdidx     (disp_oitf_rdidx ),
    .disp_oitf_rs1fpu    (disp_oitf_rs1fpu),
    .disp_oitf_rs2fpu    (disp_oitf_rs2fpu),
    .disp_oitf_rs3fpu    (disp_oitf_rs3fpu),
    .disp_oitf_rdfpu     (disp_oitf_rdfpu),
    .disp_oitf_pc        (disp_oitf_pc),


    .oitfrd_match_disprs1(oitfrd_match_disprs1),
    .oitfrd_match_disprs2(oitfrd_match_disprs2),
    .oitfrd_match_disprs3(oitfrd_match_disprs3),
    .oitfrd_match_disprd (oitfrd_match_disprd ),

    .clk                 (clk  ),
    .rst_n               (rst_n)
  );
endmodule
// --------- add/modify/delete code ---------