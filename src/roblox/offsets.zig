pub const Offsets = struct {
    pub const InstanceClassDescriptor: u32 = 0x18;
    pub const InstanceName: u32 = 0x90;
    pub const InstanceParent: u32 = 0x60;
    pub const InstanceChildren: u32 = 0x70;

    pub const ClassDescriptorName: u32 = 8;

    pub const FireServerDescriptor: u32 = 0x74C4FE0;
    pub const UnreliableFireServerDescriptor: u32 = 0x74CC400;
    pub const InvokeServerDescriptor: u32 = 0x0; // find it, me too lezy

    pub const BoundFuncDescriptorCallback: u32 = 0x88;
    pub const BoundYieldDescriptorCallback: u32 = 0x80;

    pub const ArgumentsLuaState: u32 = 0x30;
    pub const ArgumentsDescriptor: u32 = 0x40;
};
