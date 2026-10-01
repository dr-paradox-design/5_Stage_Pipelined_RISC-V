module Sign_Extend(In,ImmSrc,Imm_Ext);

    input [31:0] In;
    input [2:0] ImmSrc;   //WIDENED from [1:0] for the U-type format
    output [31:0] Imm_Ext;

    //000 = I-type : imm[11:0]  = In[31:20]
    //001 = S-type : imm[11:0]  = In[31:25], In[11:7]
    //010 = B-type : imm[12:1]  scrambled, bit 0 always 0
    //011 = U-type : imm[31:12] = In[31:12], low 12 bits ZERO. Nothing to
    //               sign-extend: the immediate already fills the top 20 bits.
    //100 = J-type : imm[20:1] scrambled as instr[31|19:12|20|30:21], bit 0 = 0.
    //               Same idea as B-type: imm[0] is never stored because jump
    //               targets are always 2-byte aligned.
    assign Imm_Ext = (ImmSrc == 3'b001) ? {{20{In[31]}}, In[31:25], In[11:7]} :
                     (ImmSrc == 3'b010) ? {{19{In[31]}}, In[31], In[7], In[30:25], In[11:8], 1'b0} :
                     (ImmSrc == 3'b011) ? {In[31:12], 12'b0} :
                     (ImmSrc == 3'b100) ? {{11{In[31]}}, In[31], In[19:12], In[20], In[30:21], 1'b0} :
                                          {{20{In[31]}}, In[31:20]};


endmodule
