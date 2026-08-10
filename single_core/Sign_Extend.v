module Sign_Extend(In,Imm_Ext);

    input [31:0] In;
    output [31:0] Imm_Ext;

    assign Imm_Ext = (In[31]) ? {{20{1'b1}}, In[31:20]} : 
                                {{20{1'b0}}, In[31:20]}; //if In[31] is 1 then Imm_Ext=In[31:20] with 20 1's else Imm_Ext=In[31:20] with 20 0's


endmodule